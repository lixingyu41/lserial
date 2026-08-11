#ifndef RUNNER_CLASSIC_BLUETOOTH_BRIDGE_H_
#define RUNNER_CLASSIC_BLUETOOTH_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

class ClassicBluetoothBridge {
 public:
  static constexpr UINT kDispatchMessage = WM_APP + 0x4C53;

  ClassicBluetoothBridge(HWND window, flutter::BinaryMessenger* messenger);
  ~ClassicBluetoothBridge();

  ClassicBluetoothBridge(const ClassicBluetoothBridge&) = delete;
  ClassicBluetoothBridge& operator=(const ClassicBluetoothBridge&) = delete;

  bool HandleWindowMessage(UINT message);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_CLASSIC_BLUETOOTH_BRIDGE_H_
