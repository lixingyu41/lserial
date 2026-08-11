#include <winsock2.h>
#include <ws2bth.h>
#include <bthioctl.h>

#include "classic_bluetooth_bridge.h"

#include <bluetoothapis.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <climits>
#include <cstdint>
#include <functional>
#include <iomanip>
#include <map>
#include <memory>
#include <mutex>
#include <queue>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResult = flutter::MethodResult<EncodableValue>;

class NativeOperationError : public std::runtime_error {
 public:
  NativeOperationError(std::string operation, std::string stage,
                       std::string native_code_type, int64_t native_code,
                       std::string message)
      : std::runtime_error(std::move(message)),
        operation(std::move(operation)),
        stage(std::move(stage)),
        native_code_type(std::move(native_code_type)),
        native_code(native_code) {}

  std::string operation;
  std::string stage;
  std::string native_code_type;
  int64_t native_code;
};

constexpr GUID kSerialPortServiceClass = {
    0x00001101,
    0x0000,
    0x1000,
    {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};

std::string Utf8FromWide(const wchar_t* value, size_t max_length) {
  if (value == nullptr || max_length == 0 || *value == L'\0') {
    return std::string();
  }
  size_t length = 0;
  while (length < max_length && value[length] != L'\0') {
    ++length;
  }
  if (length == 0 || length > static_cast<size_t>(INT_MAX)) {
    return std::string();
  }
  const int source_length = static_cast<int>(length);
  int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value,
                                 source_length, nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    size = WideCharToMultiByte(CP_UTF8, 0, value, source_length, nullptr, 0,
                               nullptr, nullptr);
  }
  if (size <= 0) {
    return std::string();
  }
  std::string result(static_cast<size_t>(size), '\0');
  const int converted = WideCharToMultiByte(
      CP_UTF8, 0, value, source_length, result.data(), size, nullptr, nullptr);
  if (converted <= 0) {
    return std::string();
  }
  result.resize(static_cast<size_t>(converted));
  return result;
}

std::string WindowsErrorMessage(DWORD code) {
  wchar_t* buffer = nullptr;
  DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, code, 0, reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
  std::string message;
  if (length > 0 && buffer != nullptr) {
    while (length > 0 &&
           (buffer[length - 1] == L'\r' || buffer[length - 1] == L'\n' ||
            buffer[length - 1] == L' ')) {
      buffer[length - 1] = L'\0';
      --length;
    }
    message = Utf8FromWide(buffer, static_cast<size_t>(length));
    LocalFree(buffer);
  }
  if (message.empty()) {
    message = "Windows error " + std::to_string(code);
  }
  return message;
}

std::string SocketErrorMessage(int code) {
  return WindowsErrorMessage(static_cast<DWORD>(code));
}

EncodableValue ErrorDetails(const std::string& operation,
                            const std::string& stage,
                            const std::string& address,
                            const std::string& native_code_type,
                            int64_t native_code,
                            const std::string& message,
                            int64_t elapsed_ms = 0) {
  EncodableMap details;
  details[EncodableValue("operation")] = EncodableValue(operation);
  details[EncodableValue("stage")] = EncodableValue(stage);
  details[EncodableValue("address")] = EncodableValue(address);
  details[EncodableValue("native_code_type")] =
      EncodableValue(native_code_type);
  details[EncodableValue("native_code")] = EncodableValue(native_code);
  details[EncodableValue("message")] = EncodableValue(message);
  if (elapsed_ms > 0) {
    details[EncodableValue("elapsed_ms")] = EncodableValue(elapsed_ms);
  }
  return EncodableValue(details);
}

int64_t ElapsedMilliseconds(
    const std::chrono::steady_clock::time_point& started_at) {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now() - started_at)
      .count();
}

std::string FormatAddress(BTH_ADDR address) {
  std::ostringstream stream;
  stream << std::uppercase << std::hex << std::setfill('0');
  for (int index = 5; index >= 0; --index) {
    if (index != 5) {
      stream << ':';
    }
    stream << std::setw(2)
           << static_cast<unsigned int>((address >> (index * 8)) & 0xFF);
  }
  return stream.str();
}

bool ParseAddress(const std::string& value, BTH_ADDR* address) {
  std::string compact;
  compact.reserve(12);
  for (char character : value) {
    if (std::isxdigit(static_cast<unsigned char>(character))) {
      compact.push_back(character);
    }
  }
  if (compact.size() != 12) {
    return false;
  }
  try {
    *address = static_cast<BTH_ADDR>(std::stoull(compact, nullptr, 16));
    return true;
  } catch (...) {
    return false;
  }
}

void DisconnectPairingAcl(HANDLE radio, BTH_ADDR address) {
  DWORD returned = 0;
  if (DeviceIoControl(radio, IOCTL_BTH_DISCONNECT_DEVICE, &address,
                      sizeof(address), nullptr, 0, &returned, nullptr) ==
      FALSE) {
    const DWORD error = GetLastError();
    if (error != ERROR_DEVICE_NOT_CONNECTED && error != ERROR_NOT_CONNECTED) {
      throw NativeOperationError("pair", "acl_disconnect", "win32", error,
                                 WindowsErrorMessage(error));
    }
  }
}

/*
 * TODO(Classic Bluetooth pairing): LSerial经典蓝牙自动配对目前不可用，以下
 * Win32认证链仅作为已尝试方案保留。实测能建立ACL，但Windows在SSP阶段
 * 返回WAIT_TIMEOUT/ERROR_NOT_AUTHENTICATED，认证回调没有完成配对。
 */
struct AuthenticationContext {
  HANDLE radio = nullptr;
  std::atomic<DWORD> callback_count{0};
  std::atomic<DWORD> response_error{ERROR_SUCCESS};
};

BOOL CALLBACK AuthenticationCallback(
    LPVOID context_value,
    PBLUETOOTH_AUTHENTICATION_CALLBACK_PARAMS parameters) {
  auto* context = static_cast<AuthenticationContext*>(context_value);
  if (context == nullptr || parameters == nullptr) {
    return FALSE;
  }

  BLUETOOTH_AUTHENTICATE_RESPONSE response{};
  response.bthAddressRemote = parameters->deviceInfo.Address;
  response.authMethod = parameters->authenticationMethod;
  response.negativeResponse = FALSE;

  switch (parameters->authenticationMethod) {
    case BLUETOOTH_AUTHENTICATION_METHOD_LEGACY:
      response.pinInfo.pin[0] = '0';
      response.pinInfo.pin[1] = '0';
      response.pinInfo.pin[2] = '0';
      response.pinInfo.pin[3] = '0';
      response.pinInfo.pinLength = 4;
      break;
    case BLUETOOTH_AUTHENTICATION_METHOD_NUMERIC_COMPARISON:
      response.numericCompInfo.NumericValue = parameters->Numeric_Value;
      break;
    case BLUETOOTH_AUTHENTICATION_METHOD_PASSKEY:
      response.passkeyInfo.passkey = 0;
      break;
    case BLUETOOTH_AUTHENTICATION_METHOD_PASSKEY_NOTIFICATION:
      response.passkeyInfo.passkey = parameters->Passkey;
      break;
    case BLUETOOTH_AUTHENTICATION_METHOD_OOB:
      response.negativeResponse = TRUE;
      break;
    default:
      response.negativeResponse = TRUE;
      break;
  }

  context->callback_count.fetch_add(1);
  const DWORD error =
      BluetoothSendAuthenticationResponseEx(context->radio, &response);
  context->response_error.store(error);
  return error == ERROR_SUCCESS ? TRUE : FALSE;
}

DWORD PairDeviceWithWin32(HWND window, HANDLE radio,
                          BLUETOOTH_DEVICE_INFO* device) {
  if (device == nullptr) {
    return ERROR_INVALID_PARAMETER;
  }

  AuthenticationContext context;
  context.radio = radio;
  HBLUETOOTH_AUTHENTICATION_REGISTRATION registration = nullptr;
  DWORD error = BluetoothRegisterForAuthenticationEx(
      device, &registration, AuthenticationCallback, &context);
  if (error != ERROR_SUCCESS) {
    return error;
  }

  error = BluetoothAuthenticateDeviceEx(
      window, radio, device, nullptr,
      MITMProtectionNotRequiredGeneralBonding);
  BluetoothUnregisterAuthentication(registration);

  const DWORD response_error = context.response_error.load();
  if (error == ERROR_SUCCESS && response_error != ERROR_SUCCESS) {
    return response_error;
  }
  return error;
}

DWORD PairDeviceWithAssociationEndpoint(BTH_ADDR address) {
  using winrt::Windows::Devices::Bluetooth::BluetoothDevice;
  using winrt::Windows::Devices::Enumeration::DeviceInformation;
  using winrt::Windows::Devices::Enumeration::DeviceInformationKind;
  using winrt::Windows::Devices::Enumeration::DevicePairingKinds;
  using winrt::Windows::Devices::Enumeration::DevicePairingProtectionLevel;
  using winrt::Windows::Devices::Enumeration::DevicePairingResultStatus;

  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    const auto properties = winrt::single_threaded_vector<winrt::hstring>();
    properties.Append(L"System.Devices.Aep.DeviceAddress");
    /*
     * 该路径复用了独立ClassicSppTest曾成功的AssociationEndpoint查询方式，
     * 代替FromBluetoothAddressAsync返回的非配对端点；集成到LSerial MCP后
     * 当前仍会超时，因此暂时保留用于后续继续定位，不能视为已验证接口。
     */
    const auto devices = DeviceInformation::FindAllAsync(
                             BluetoothDevice::GetDeviceSelectorFromPairingState(
                                 false),
                             properties, DeviceInformationKind::AssociationEndpoint)
                             .get();

    DeviceInformation target{nullptr};
    for (const auto& device : devices) {
      const auto values = device.Properties();
      const winrt::hstring key = L"System.Devices.Aep.DeviceAddress";
      if (!values.HasKey(key)) {
        continue;
      }
      const auto value = values.Lookup(key);
      if (value == nullptr) {
        continue;
      }
      const auto address_text = winrt::unbox_value_or<winrt::hstring>(
          value, winrt::hstring{});
      BTH_ADDR candidate = 0;
      if (ParseAddress(winrt::to_string(address_text), &candidate) &&
          candidate == address) {
        target = device;
        break;
      }
    }
    if (target == nullptr) {
      return ERROR_NOT_FOUND;
    }
    if (target.Pairing().IsPaired()) {
      return ERROR_SUCCESS;
    }

    const auto custom = target.Pairing().Custom();
    const auto token = custom.PairingRequested(
        [](const auto&, const auto& event) {
          if (event.PairingKind() == DevicePairingKinds::ProvidePin) {
            event.Accept(L"0000");
          } else {
            event.Accept();
          }
        });
    const DevicePairingKinds kinds =
        DevicePairingKinds::ConfirmOnly | DevicePairingKinds::ProvidePin |
        DevicePairingKinds::ConfirmPinMatch;
    const auto pairing_result =
        custom.PairAsync(kinds, DevicePairingProtectionLevel::Default).get();
    custom.PairingRequested(token);

    if (pairing_result.Status() == DevicePairingResultStatus::Paired ||
        pairing_result.Status() == DevicePairingResultStatus::AlreadyPaired) {
      return ERROR_SUCCESS;
    }
    const int status = static_cast<int>(pairing_result.Status());
    throw NativeOperationError(
        "pair", "association_endpoint_pairing", "winrt_status", status,
        "Windows AssociationEndpoint pairing status=" +
            std::to_string(status));
  } catch (const winrt::hresult_error& error) {
    return static_cast<DWORD>(error.code().value);
  }
}

SOCKADDR_BTH DiscoverSerialPortService(BTH_ADDR address) {
  SOCKADDR_BTH peer{};
  peer.addressFamily = AF_BTH;
  peer.btAddr = address;

  wchar_t context[64]{};
  DWORD context_length = static_cast<DWORD>(std::size(context));
  if (WSAAddressToStringW(reinterpret_cast<LPSOCKADDR>(&peer), sizeof(peer),
                          nullptr, context, &context_length) == SOCKET_ERROR) {
    const int error = WSAGetLastError();
    throw NativeOperationError("connect", "sdp_address", "wsa", error,
                               SocketErrorMessage(error));
  }

  WSAQUERYSETW query{};
  query.dwSize = sizeof(query);
  query.lpServiceClassId = const_cast<GUID*>(&kSerialPortServiceClass);
  query.dwNameSpace = NS_BTH;
  query.lpszContext = context;
  query.dwNumberOfCsAddrs = 0;

  constexpr DWORD kLookupFlags = LUP_FLUSHCACHE | LUP_RETURN_ADDR;
  HANDLE lookup = nullptr;
  if (WSALookupServiceBeginW(&query, kLookupFlags, &lookup) == SOCKET_ERROR) {
    const int error = WSAGetLastError();
    throw NativeOperationError("connect", "sdp_begin", "wsa", error,
                               SocketErrorMessage(error));
  }

  std::vector<uint8_t> buffer(4096);
  SOCKADDR_BTH service{};
  int lookup_error = WSASERVICE_NOT_FOUND;
  for (;;) {
    DWORD buffer_length = static_cast<DWORD>(buffer.size());
    auto* result = reinterpret_cast<WSAQUERYSETW*>(buffer.data());
    result->dwSize = sizeof(WSAQUERYSETW);
    if (WSALookupServiceNextW(lookup, kLookupFlags, &buffer_length, result) ==
        SOCKET_ERROR) {
      lookup_error = WSAGetLastError();
      if (lookup_error == WSAEFAULT && buffer_length > buffer.size()) {
        buffer.resize(buffer_length);
        continue;
      }
      break;
    }
    if (result->dwNumberOfCsAddrs == 0 || result->lpcsaBuffer == nullptr ||
        result->lpcsaBuffer[0].LocalAddr.lpSockaddr == nullptr ||
        result->lpcsaBuffer[0].LocalAddr.iSockaddrLength <
            static_cast<int>(sizeof(SOCKADDR_BTH))) {
      lookup_error = WSAEINVALIDPROCTABLE;
      break;
    }
    service = *reinterpret_cast<const SOCKADDR_BTH*>(
        result->lpcsaBuffer[0].LocalAddr.lpSockaddr);
    lookup_error = 0;
    break;
  }
  WSALookupServiceEnd(lookup);

  if (lookup_error != 0) {
    throw NativeOperationError("connect", "sdp_query", "wsa", lookup_error,
                               SocketErrorMessage(lookup_error));
  }
  if (service.addressFamily != AF_BTH || service.port == 0) {
    throw NativeOperationError(
        "connect", "sdp_result", "wsa", WSASERVICE_NOT_FOUND,
        "The Serial Port service did not return a connectable RFCOMM channel.");
  }
  service.btAddr = address;
  service.serviceClassId = GUID_NULL;
  return service;
}

struct DeviceRecord {
  BLUETOOTH_DEVICE_INFO info{sizeof(BLUETOOTH_DEVICE_INFO)};
  HANDLE radio = nullptr;
};

void CloseDeviceRecord(DeviceRecord* record) {
  if (record != nullptr && record->radio != nullptr) {
    CloseHandle(record->radio);
    record->radio = nullptr;
  }
}

EncodableValue DeviceValue(const BLUETOOTH_DEVICE_INFO& info) {
  EncodableMap value;
  value[EncodableValue("address")] =
      EncodableValue(FormatAddress(info.Address.ullLong));
  value[EncodableValue("name")] = EncodableValue(
      Utf8FromWide(info.szName, sizeof(info.szName) / sizeof(info.szName[0])));
  value[EncodableValue("paired")] = EncodableValue(info.fAuthenticated != 0);
  value[EncodableValue("connected")] = EncodableValue(info.fConnected != 0);
  value[EncodableValue("remembered")] = EncodableValue(info.fRemembered != 0);
  return EncodableValue(value);
}

EncodableValue PairDeviceValue(const BLUETOOTH_DEVICE_INFO& info) {
  EncodableMap value;
  value[EncodableValue("address")] =
      EncodableValue(FormatAddress(info.Address.ullLong));
  value[EncodableValue("name")] = EncodableValue(std::string());
  value[EncodableValue("paired")] = EncodableValue(info.fAuthenticated != 0);
  value[EncodableValue("connected")] = EncodableValue(info.fConnected != 0);
  value[EncodableValue("remembered")] = EncodableValue(info.fRemembered != 0);
  return EncodableValue(value);
}

std::vector<BLUETOOTH_DEVICE_INFO> EnumerateDevices(int timeout_ms,
                                                    bool inquiry) {
  std::map<BTH_ADDR, BLUETOOTH_DEVICE_INFO> devices;
  BLUETOOTH_FIND_RADIO_PARAMS radio_params{sizeof(
      BLUETOOTH_FIND_RADIO_PARAMS)};
  HANDLE radio = nullptr;
  HBLUETOOTH_RADIO_FIND radio_find =
      BluetoothFindFirstRadio(&radio_params, &radio);
  if (radio_find == nullptr) {
    const DWORD error = GetLastError();
    const std::string message =
        error == ERROR_NO_MORE_ITEMS
            ? "No enabled Bluetooth radio was found."
            : WindowsErrorMessage(error);
    throw NativeOperationError("scan", "radio_discovery", "win32", error,
                               message);
  }

  do {
    BLUETOOTH_DEVICE_SEARCH_PARAMS search_params{
        sizeof(BLUETOOTH_DEVICE_SEARCH_PARAMS)};
    search_params.fReturnAuthenticated = TRUE;
    search_params.fReturnRemembered = TRUE;
    search_params.fReturnUnknown = TRUE;
    search_params.fReturnConnected = TRUE;
    search_params.fIssueInquiry = inquiry ? TRUE : FALSE;
    search_params.cTimeoutMultiplier = static_cast<UCHAR>(
        inquiry ? std::clamp(timeout_ms / 1280, 1, 48) : 0);
    search_params.hRadio = radio;

    BLUETOOTH_DEVICE_INFO info{sizeof(BLUETOOTH_DEVICE_INFO)};
    HBLUETOOTH_DEVICE_FIND device_find =
        BluetoothFindFirstDevice(&search_params, &info);
    if (device_find != nullptr) {
      do {
        devices[info.Address.ullLong] = info;
        info = BLUETOOTH_DEVICE_INFO{sizeof(BLUETOOTH_DEVICE_INFO)};
      } while (BluetoothFindNextDevice(device_find, &info));
      BluetoothFindDeviceClose(device_find);
    }
    CloseHandle(radio);
    radio = nullptr;
  } while (BluetoothFindNextRadio(radio_find, &radio));

  BluetoothFindRadioClose(radio_find);
  std::vector<BLUETOOTH_DEVICE_INFO> result;
  result.reserve(devices.size());
  for (const auto& entry : devices) {
    result.push_back(entry.second);
  }
  std::sort(result.begin(), result.end(),
            [](const BLUETOOTH_DEVICE_INFO& left,
               const BLUETOOTH_DEVICE_INFO& right) {
              const std::string left_name = Utf8FromWide(
                  left.szName, sizeof(left.szName) / sizeof(left.szName[0]));
              const std::string right_name = Utf8FromWide(
                  right.szName,
                  sizeof(right.szName) / sizeof(right.szName[0]));
              if (left.fAuthenticated != right.fAuthenticated) {
                return left.fAuthenticated > right.fAuthenticated;
              }
              return left_name < right_name;
            });
  return result;
}

DeviceRecord FindDevice(BTH_ADDR address, bool inquiry) {
  BLUETOOTH_FIND_RADIO_PARAMS radio_params{sizeof(
      BLUETOOTH_FIND_RADIO_PARAMS)};
  HANDLE radio = nullptr;
  HBLUETOOTH_RADIO_FIND radio_find =
      BluetoothFindFirstRadio(&radio_params, &radio);
  if (radio_find == nullptr) {
    const DWORD error = GetLastError();
    const std::string message =
        error == ERROR_NO_MORE_ITEMS
            ? "No enabled Bluetooth radio was found."
            : WindowsErrorMessage(error);
    throw NativeOperationError("pair", "radio_discovery", "win32", error,
                               message);
  }

  do {
    BLUETOOTH_DEVICE_SEARCH_PARAMS search_params{
        sizeof(BLUETOOTH_DEVICE_SEARCH_PARAMS)};
    search_params.fReturnAuthenticated = TRUE;
    search_params.fReturnRemembered = TRUE;
    search_params.fReturnUnknown = TRUE;
    search_params.fReturnConnected = TRUE;
    search_params.fIssueInquiry = inquiry ? TRUE : FALSE;
    search_params.cTimeoutMultiplier = inquiry ? 4 : 0;
    search_params.hRadio = radio;
    BLUETOOTH_DEVICE_INFO info{sizeof(BLUETOOTH_DEVICE_INFO)};
    HBLUETOOTH_DEVICE_FIND device_find =
        BluetoothFindFirstDevice(&search_params, &info);
    if (device_find != nullptr) {
      do {
        if (info.Address.ullLong == address) {
          BluetoothFindDeviceClose(device_find);
          BluetoothFindRadioClose(radio_find);
          return DeviceRecord{info, radio};
        }
        info = BLUETOOTH_DEVICE_INFO{sizeof(BLUETOOTH_DEVICE_INFO)};
      } while (BluetoothFindNextDevice(device_find, &info));
      BluetoothFindDeviceClose(device_find);
    }
    CloseHandle(radio);
    radio = nullptr;
  } while (BluetoothFindNextRadio(radio_find, &radio));

  BluetoothFindRadioClose(radio_find);
  throw NativeOperationError(
      "pair", "device_discovery", "win32", ERROR_NOT_FOUND,
      "Bluetooth device was not found. Scan again first.");
}

const EncodableMap* ArgumentsOf(
    const flutter::MethodCall<EncodableValue>& call) {
  return call.arguments() == nullptr
             ? nullptr
             : std::get_if<EncodableMap>(call.arguments());
}

std::string StringArgument(const EncodableMap* arguments,
                           const char* name) {
  if (arguments == nullptr) {
    return std::string();
  }
  const auto iterator = arguments->find(EncodableValue(name));
  if (iterator == arguments->end()) {
    return std::string();
  }
  const auto* value = std::get_if<std::string>(&iterator->second);
  return value == nullptr ? std::string() : *value;
}

int IntArgument(const EncodableMap* arguments, const char* name,
                int fallback) {
  if (arguments == nullptr) {
    return fallback;
  }
  const auto iterator = arguments->find(EncodableValue(name));
  if (iterator == arguments->end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

const std::vector<uint8_t>* BytesArgument(const EncodableMap* arguments,
                                          const char* name) {
  if (arguments == nullptr) {
    return nullptr;
  }
  const auto iterator = arguments->find(EncodableValue(name));
  return iterator == arguments->end()
             ? nullptr
             : std::get_if<std::vector<uint8_t>>(&iterator->second);
}

}  // namespace

struct ClassicBluetoothBridge::Impl {
  struct Session {
    std::atomic<SOCKET> socket{INVALID_SOCKET};
    std::atomic<bool> stopping{false};
    std::mutex send_mutex;

    void CloseSocket() {
      const SOCKET socket_handle = socket.exchange(INVALID_SOCKET);
      if (socket_handle != INVALID_SOCKET) {
        ::shutdown(socket_handle, SD_BOTH);
        closesocket(socket_handle);
      }
    }
  };

  struct State : std::enable_shared_from_this<State> {
    explicit State(HWND window) : window(window) {}

    HWND window;
    std::atomic<bool> active{true};
    std::mutex queue_mutex;
    std::queue<std::function<void()>> queue;
    std::mutex sessions_mutex;
    std::map<std::string, std::shared_ptr<Session>> sessions;
    std::shared_ptr<flutter::MethodChannel<EncodableValue>> channel;

    void Post(std::function<void()> callback) {
      if (!active.load()) {
        return;
      }
      {
        std::lock_guard<std::mutex> lock(queue_mutex);
        queue.push(std::move(callback));
      }
      PostMessage(window, ClassicBluetoothBridge::kDispatchMessage, 0, 0);
    }

    void Drain() {
      std::queue<std::function<void()>> pending;
      {
        std::lock_guard<std::mutex> lock(queue_mutex);
        pending.swap(queue);
      }
      while (!pending.empty()) {
        pending.front()();
        pending.pop();
      }
    }

    void CloseAll() {
      std::vector<std::shared_ptr<Session>> pending;
      {
        std::lock_guard<std::mutex> lock(sessions_mutex);
        for (const auto& entry : sessions) {
          pending.push_back(entry.second);
        }
        sessions.clear();
      }
      for (const auto& session : pending) {
        session->stopping.store(true);
        session->CloseSocket();
      }
    }
  };

  Impl(HWND window, flutter::BinaryMessenger* messenger)
      : state(std::make_shared<State>(window)) {
    WSADATA winsock_data{};
    const int startup_error = WSAStartup(MAKEWORD(2, 2), &winsock_data);
    if (startup_error != 0) {
      throw std::runtime_error(SocketErrorMessage(startup_error));
    }
    state->channel =
        std::make_shared<flutter::MethodChannel<EncodableValue>>(
            messenger, "lserial/classic_bluetooth",
            &flutter::StandardMethodCodec::GetInstance());
    state->channel->SetMethodCallHandler(
        [this](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<MethodResult> result) {
          HandleMethodCall(call, std::move(result));
        });
  }

  ~Impl() {
    state->active.store(false);
    state->CloseAll();
    state->channel->SetMethodCallHandler(nullptr);
    state->channel.reset();
  }

  void HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                        std::unique_ptr<MethodResult> result) {
    const EncodableMap* arguments = ArgumentsOf(call);
    const std::string method = call.method_name();
    if (method == "scan") {
      Scan(IntArgument(arguments, "timeout_ms", 6000), std::move(result));
      return;
    }
    if (method == "pair") {
      Pair(StringArgument(arguments, "address"), std::move(result));
      return;
    }
    if (method == "unpair") {
      Unpair(StringArgument(arguments, "address"), std::move(result));
      return;
    }
    if (method == "connect") {
      Connect(StringArgument(arguments, "session_id"),
              StringArgument(arguments, "address"),
              IntArgument(arguments, "rfcomm_channel", 0),
              std::move(result));
      return;
    }
    if (method == "send") {
      const auto* bytes = BytesArgument(arguments, "data");
      Send(StringArgument(arguments, "session_id"),
           bytes == nullptr ? std::vector<uint8_t>() : *bytes,
           std::move(result));
      return;
    }
    if (method == "disconnect") {
      Disconnect(StringArgument(arguments, "session_id"), std::move(result));
      return;
    }
    result->NotImplemented();
  }

  void Scan(int timeout_ms, std::unique_ptr<MethodResult> result) {
    auto shared_result = std::shared_ptr<MethodResult>(std::move(result));
    const auto shared_state = state;
    std::thread([shared_state, shared_result, timeout_ms]() {
      const auto started_at = std::chrono::steady_clock::now();
      try {
        EncodableList values;
        for (const auto& device : EnumerateDevices(timeout_ms, true)) {
          values.push_back(DeviceValue(device));
        }
        shared_state->Post([shared_result, values = std::move(values)]() {
          shared_result->Success(EncodableValue(values));
        });
      } catch (const NativeOperationError& error) {
        const std::string message = error.what();
        const EncodableValue details = ErrorDetails(
            error.operation, error.stage, std::string(),
            error.native_code_type, error.native_code, message,
            ElapsedMilliseconds(started_at));
        shared_state->Post([shared_result, message, details]() {
          shared_result->Error("classic_bluetooth_scan_failed", message,
                               details);
        });
      } catch (const std::exception& error) {
        const std::string message = error.what();
        const EncodableValue details = ErrorDetails(
            "scan", "device_discovery", std::string(), "internal", 0,
            message, ElapsedMilliseconds(started_at));
        shared_state->Post([shared_result, message, details]() {
          shared_result->Error("classic_bluetooth_scan_failed", message,
                               details);
        });
      }
    }).detach();
  }

  void Pair(const std::string& address_text,
            std::unique_ptr<MethodResult> result) {
    BTH_ADDR address = 0;
    if (!ParseAddress(address_text, &address)) {
      const std::string message = "Invalid Bluetooth address.";
      result->Error(
          "classic_bluetooth_invalid_address", message,
          ErrorDetails("pair", "request", address_text, "validation", 0,
                       message));
      return;
    }
    auto shared_result = std::shared_ptr<MethodResult>(std::move(result));
    const auto shared_state = state;
    std::thread([shared_state, shared_result, address]() {
      const auto started_at = std::chrono::steady_clock::now();
      const std::string address_text = FormatAddress(address);
      DeviceRecord record;
      try {
        record = FindDevice(address, true);
        if (!record.info.fAuthenticated) {
          const DWORD error = PairDeviceWithAssociationEndpoint(address);
          if (error != ERROR_SUCCESS) {
            throw NativeOperationError(
                "pair", "authentication", "win32", error,
                WindowsErrorMessage(error));
          }
          record.info = BLUETOOTH_DEVICE_INFO{sizeof(BLUETOOTH_DEVICE_INFO)};
          record.info.Address.ullLong = address;
          const DWORD refresh_error =
              BluetoothGetDeviceInfo(record.radio, &record.info);
          if (refresh_error != ERROR_SUCCESS) {
            throw NativeOperationError(
                "pair", "verification", "win32", refresh_error,
                WindowsErrorMessage(refresh_error));
          }
        }
        if (!record.info.fAuthenticated) {
          throw NativeOperationError(
              "pair", "verification", "win32", ERROR_NOT_AUTHENTICATED,
              "Windows did not report the Bluetooth device as authenticated.");
        }
        // LSerial owns the RFCOMM socket directly. Do not install or remove the
        // Windows COM-port profile here; changing profile state while the SSP
        // ACL is still active can leave that ACL unusable for the first socket.
        DisconnectPairingAcl(record.radio, address);
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        const EncodableValue value = PairDeviceValue(record.info);
        CloseDeviceRecord(&record);
        shared_state->Post(
            [shared_result, value]() { shared_result->Success(value); });
      } catch (const NativeOperationError& error) {
        CloseDeviceRecord(&record);
        const std::string message =
            "Windows Bluetooth " + error.stage + " failed (" +
            error.native_code_type + "=" + std::to_string(error.native_code) +
            ").";
        const EncodableValue details = ErrorDetails(
            error.operation, error.stage, address_text,
            error.native_code_type, error.native_code, message,
            ElapsedMilliseconds(started_at));
        shared_state->Post([shared_result, message, details]() {
          shared_result->Error("classic_bluetooth_pair_failed", message,
                               details);
        });
      } catch (const std::exception&) {
        CloseDeviceRecord(&record);
        const std::string message =
            "Internal Bluetooth pairing operation failed.";
        const EncodableValue details = ErrorDetails(
            "pair", "authentication", address_text, "internal", 0, message,
            ElapsedMilliseconds(started_at));
        shared_state->Post([shared_result, message, details]() {
          shared_result->Error("classic_bluetooth_pair_failed", message,
                               details);
        });
      }
    }).detach();
  }

  void Unpair(const std::string& address_text,
              std::unique_ptr<MethodResult> result) {
    BTH_ADDR address = 0;
    if (!ParseAddress(address_text, &address)) {
      const std::string message = "Invalid Bluetooth address.";
      result->Error(
          "classic_bluetooth_invalid_address", message,
          ErrorDetails("unpair", "request", address_text, "validation", 0,
                       message));
      return;
    }
    auto shared_result = std::shared_ptr<MethodResult>(std::move(result));
    const auto shared_state = state;
    std::thread([shared_state, shared_result, address]() {
      const auto started_at = std::chrono::steady_clock::now();
      const std::string address_text = FormatAddress(address);
      BLUETOOTH_ADDRESS bluetooth_address{};
      bluetooth_address.ullLong = address;
      const DWORD error = BluetoothRemoveDevice(&bluetooth_address);
      const int64_t elapsed_ms = ElapsedMilliseconds(started_at);
      shared_state->Post([shared_result, error, address_text, elapsed_ms]() {
        if (error == ERROR_SUCCESS) {
          shared_result->Success();
        } else {
          const std::string message = WindowsErrorMessage(error);
          shared_result->Error(
              "classic_bluetooth_unpair_failed", message,
              ErrorDetails("unpair", "remove_pairing", address_text,
                           "win32", error, message, elapsed_ms));
        }
      });
    }).detach();
  }

  void Connect(const std::string& session_id, const std::string& address_text,
               int rfcomm_channel,
               std::unique_ptr<MethodResult> result) {
    if (session_id.empty()) {
      const std::string message = "Missing Bluetooth session ID.";
      result->Error(
          "classic_bluetooth_invalid_session", message,
          ErrorDetails("connect", "request", address_text, "validation", 0,
                       message));
      return;
    }
    BTH_ADDR address = 0;
    if (!ParseAddress(address_text, &address)) {
      const std::string message = "Invalid Bluetooth address.";
      result->Error(
          "classic_bluetooth_invalid_address", message,
          ErrorDetails("connect", "request", address_text, "validation", 0,
                       message));
      return;
    }
    if (rfcomm_channel < 0 || rfcomm_channel > 30) {
      const std::string message = "RFCOMM channel must be between 0 and 30.";
      result->Error(
          "classic_bluetooth_invalid_channel", message,
          ErrorDetails("connect", "request", address_text, "validation", 0,
                       message));
      return;
    }
    auto shared_result = std::shared_ptr<MethodResult>(std::move(result));
    const auto shared_state = state;
    std::thread([shared_state, shared_result, session_id, address,
                 rfcomm_channel]() {
      const auto started_at = std::chrono::steady_clock::now();
      const std::string address_text = FormatAddress(address);
      SOCKET socket_handle =
          socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
      if (socket_handle == INVALID_SOCKET) {
        const int error = WSAGetLastError();
        const std::string message = SocketErrorMessage(error);
        const EncodableValue details = ErrorDetails(
            "connect", "socket_create", address_text, "wsa", error, message,
            ElapsedMilliseconds(started_at));
        shared_state->Post([shared_result, message, details]() {
          shared_result->Error("classic_bluetooth_connect_failed", message,
                               details);
        });
        return;
      }

      SOCKADDR_BTH target{};
      if (rfcomm_channel > 0) {
        target.addressFamily = AF_BTH;
        target.btAddr = address;
        target.serviceClassId = GUID_NULL;
        target.port = static_cast<ULONG>(rfcomm_channel);
      } else {
        // Let the Windows Bluetooth provider resolve the remote SPP service.
        // This binds the socket to the installed Serial Port profile and avoids
        // racing a separate WSALookupService query against profile discovery.
        target.addressFamily = AF_BTH;
        target.btAddr = address;
        target.serviceClassId = kSerialPortServiceClass;
        target.port = 0;
      }
      if (::connect(socket_handle, reinterpret_cast<SOCKADDR*>(&target),
                    sizeof(target)) == SOCKET_ERROR) {
        const int error = WSAGetLastError();
        closesocket(socket_handle);
        const std::string message = SocketErrorMessage(error);
        const EncodableValue details = ErrorDetails(
            "connect", "service_connect", address_text, "wsa", error,
            message, ElapsedMilliseconds(started_at));
        shared_state->Post([shared_result, message, details]() {
          shared_result->Error("classic_bluetooth_connect_failed", message,
                               details);
        });
        return;
      }

      const auto session = std::make_shared<Session>();
      session->socket.store(socket_handle);
      {
        std::lock_guard<std::mutex> lock(shared_state->sessions_mutex);
        const auto existing = shared_state->sessions.find(session_id);
        if (existing != shared_state->sessions.end()) {
          existing->second->stopping.store(true);
          existing->second->CloseSocket();
        }
        shared_state->sessions[session_id] = session;
      }

      shared_state->Post(
          [shared_result]() { shared_result->Success(); });
      std::thread([shared_state, session, session_id, address]() {
        std::vector<uint8_t> buffer(4096);
        int received = 0;
        while (!session->stopping.load() &&
               (received = ::recv(session->socket.load(),
                                  reinterpret_cast<char*>(buffer.data()),
                                  static_cast<int>(buffer.size()), 0)) > 0) {
          std::vector<uint8_t> data(buffer.begin(), buffer.begin() + received);
          shared_state->Post([shared_state, session_id,
                              data = std::move(data)]() {
            if (shared_state->channel == nullptr) {
              return;
            }
            EncodableMap arguments;
            arguments[EncodableValue("session_id")] =
                EncodableValue(session_id);
            arguments[EncodableValue("data")] = EncodableValue(data);
            shared_state->channel->InvokeMethod(
                "data", std::make_unique<EncodableValue>(arguments));
          });
        }

        const int error = received == SOCKET_ERROR ? WSAGetLastError() : 0;
        const bool unexpected = !session->stopping.exchange(true);
        session->CloseSocket();
        {
          std::lock_guard<std::mutex> lock(shared_state->sessions_mutex);
          const auto current = shared_state->sessions.find(session_id);
          if (current != shared_state->sessions.end() &&
              current->second == session) {
            shared_state->sessions.erase(current);
          }
        }
        if (unexpected) {
          const std::string message =
              error == 0 ? "Bluetooth device disconnected."
                         : SocketErrorMessage(error);
          const std::string address_text = FormatAddress(address);
          shared_state->Post([shared_state, session_id, message, error,
                              address_text]() {
            if (shared_state->channel == nullptr) {
              return;
            }
            EncodableMap arguments;
            arguments[EncodableValue("session_id")] =
                EncodableValue(session_id);
            arguments[EncodableValue("message")] = EncodableValue(message);
            arguments[EncodableValue("operation")] =
                EncodableValue("receive");
            arguments[EncodableValue("stage")] = EncodableValue("read");
            arguments[EncodableValue("address")] =
                EncodableValue(address_text);
            arguments[EncodableValue("native_code_type")] =
                EncodableValue(error == 0 ? "internal" : "wsa");
            arguments[EncodableValue("native_code")] =
                EncodableValue(static_cast<int64_t>(error));
            shared_state->channel->InvokeMethod(
                "disconnected",
                std::make_unique<EncodableValue>(arguments));
          });
        }
      }).detach();
    }).detach();
  }

  void Send(const std::string& session_id, std::vector<uint8_t> bytes,
            std::unique_ptr<MethodResult> result) {
    std::shared_ptr<Session> session;
    {
      std::lock_guard<std::mutex> lock(state->sessions_mutex);
      const auto iterator = state->sessions.find(session_id);
      if (iterator != state->sessions.end()) {
        session = iterator->second;
      }
    }
    if (session == nullptr || session->stopping.load()) {
      const std::string message = "Bluetooth session is not connected.";
      result->Error(
          "classic_bluetooth_not_connected", message,
          ErrorDetails("send", "write", std::string(), "state", 0, message));
      return;
    }
    auto shared_result = std::shared_ptr<MethodResult>(std::move(result));
    const auto shared_state = state;
    std::thread([shared_state, shared_result, session,
                 bytes = std::move(bytes)]() {
      std::lock_guard<std::mutex> send_lock(session->send_mutex);
      size_t offset = 0;
      while (offset < bytes.size() && !session->stopping.load()) {
        const SOCKET socket_handle = session->socket.load();
        if (socket_handle == INVALID_SOCKET) {
          break;
        }
        const int sent = ::send(
            socket_handle,
            reinterpret_cast<const char*>(bytes.data() + offset),
            static_cast<int>(bytes.size() - offset), 0);
        if (sent == SOCKET_ERROR) {
          const int error = WSAGetLastError();
          const std::string message = SocketErrorMessage(error);
          const EncodableValue details = ErrorDetails(
              "send", "write", std::string(), "wsa", error, message);
          shared_state->Post([shared_result, message, details]() {
            shared_result->Error("classic_bluetooth_send_failed", message,
                                 details);
          });
          return;
        }
        offset += static_cast<size_t>(sent);
      }
      if (offset != bytes.size()) {
        const std::string message =
            "Bluetooth device disconnected during send.";
        const EncodableValue details = ErrorDetails(
            "send", "write", std::string(), "state", 0, message);
        shared_state->Post([shared_result, message, details]() {
          shared_result->Error("classic_bluetooth_send_failed", message,
                               details);
        });
        return;
      }
      shared_state->Post([shared_result]() { shared_result->Success(); });
    }).detach();
  }

  void Disconnect(const std::string& session_id,
                  std::unique_ptr<MethodResult> result) {
    std::shared_ptr<Session> session;
    {
      std::lock_guard<std::mutex> lock(state->sessions_mutex);
      const auto iterator = state->sessions.find(session_id);
      if (iterator != state->sessions.end()) {
        session = iterator->second;
        state->sessions.erase(iterator);
      }
    }
    if (session != nullptr) {
      session->stopping.store(true);
      session->CloseSocket();
    }
    result->Success();
  }

  std::shared_ptr<State> state;
};

ClassicBluetoothBridge::ClassicBluetoothBridge(
    HWND window, flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(window, messenger)) {}

ClassicBluetoothBridge::~ClassicBluetoothBridge() = default;

bool ClassicBluetoothBridge::HandleWindowMessage(UINT message) {
  if (message != kDispatchMessage || impl_ == nullptr) {
    return false;
  }
  impl_->state->Drain();
  return true;
}
