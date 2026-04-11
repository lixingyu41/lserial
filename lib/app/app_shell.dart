import 'package:flutter/material.dart';

import '../application/session_controller.dart';
import '../features/connection/connection_panel.dart';
import '../features/console/console_panel.dart';
import '../features/send_panel/send_panel.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 980) {
                return Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ConnectionPanel(controller: controller),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      flex: 4,
                      child: ConsolePanel(controller: controller),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      flex: 3,
                      child: SendPanel(controller: controller),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(
                      width: 330,
                      child: ConnectionPanel(controller: controller)),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: ConsolePanel(controller: controller)),
                        const Divider(height: 1),
                        SizedBox(
                            height: 230,
                            child: SendPanel(controller: controller)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
