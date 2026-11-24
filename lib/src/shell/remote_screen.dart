import 'package:flutter/material.dart';

import '../remote/service.dart';
import 'controls.dart';
import 'navigation.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.service});
  final RemoteScreenService service;
  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  String page = 'choose', address = '', code = '';
  RemoteScreenService get remote => widget.service;
  Widget button(String text, VoidCallback action, {bool autofocus = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ConsoleButton(
          onPressed: action,
          autofocus: autofocus,
          child: Text(text),
        ),
      );
  @override
  void dispose() {
    if (remote.connected || remote.connecting) remote.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: remote,
    builder: (context, _) {
      if (remote.connected) {
        final image = remote.frame;
        return Column(
          children: [
            Expanded(
              child: image == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          remote.status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    )
                  : Image.memory(
                      image,
                      cacheWidth: 640,
                      cacheHeight: 480,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      frameBuilder: (context, child, frame, sync) {
                        if (frame != null)
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => remote.frameDisplayed(),
                          );
                        return child;
                      },
                      errorBuilder: (context, error, stack) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => remote.frameDisplayed(),
                        );
                        return const Center(
                          child: Text('Could not decode the remote frame.'),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Connected to ${remote.clientHost}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.end,
                    children: [
                      if (remote.frame == null)
                        ConsoleButton(
                          onPressed: remote.retryCapture,
                          child: const Text('Retry screen'),
                        ),
                      ConsoleButton(
                        onPressed: remote.disconnect,
                        child: const Text('Disconnect'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      }
      return ConsoleScrollView(
        padding: EdgeInsets.all(
          consoleSideInset(MediaQuery.sizeOf(context).width),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Remote screen', style: TextStyle(fontSize: 32)),
                const SizedBox(height: 24),
                if (page == 'choose') ...[
                  button('Use this device as a host', () {
                    setState(() => page = 'host');
                    remote.refreshAddresses();
                  }, autofocus: true),
                  button('Use this device as a remote screen', () {
                    setState(() => page = 'client');
                    remote.discover();
                  }),
                ],
                if (page == 'host') ...[
                  if (remote.canHost) ...[
                    Text(
                      remote.port == null
                          ? 'The remote server is unavailable.'
                          : 'The server runs whenever Broomm is open.',
                    ),
                    const SizedBox(height: 16),
                    for (final ip in remote.addresses)
                      SelectableText(
                        '$ip:${remote.port ?? 43187}',
                        style: const TextStyle(fontSize: 24),
                      ),
                    const SizedBox(height: 16),
                    SelectableText(
                      'Connection code  ${remote.history.code}',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'On the other device, open Remote screen, choose Use this device as a remote screen, and enter an address above and this connection code. Launch melonDS or Azahar after connecting.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      remote.hasGuest
                          ? 'A remote screen is connected.'
                          : 'Waiting for a remote screen.',
                    ),
                  ] else
                    const Text(
                      'Hosting is currently available on macOS. This device can connect as a remote screen.',
                    ),
                ],
                if (page == 'client') ...[
                  if (remote.history.hosts.isNotEmpty) ...[
                    const Text('Recent hosts'),
                    const SizedBox(height: 12),
                    for (final host in remote.history.hosts)
                      button(
                        host['address']!,
                        () => remote.connect(host['address']!, host['code']!),
                      ),
                  ],
                  if (remote.discovered.isNotEmpty) ...[
                    const Text('Nearby hosts'),
                    const SizedBox(height: 12),
                    for (final host in remote.discovered)
                      button(host, () => setState(() => address = host)),
                  ],
                  ConsoleField(
                    label: 'Host address',
                    hint: '192.168.1.20:43187',
                    value: address,
                    onChanged: (v) => address = v,
                  ),
                  const SizedBox(height: 16),
                  ConsoleField(
                    label: 'Connection code',
                    value: code,
                    onChanged: (v) => code = v,
                  ),
                  const SizedBox(height: 16),
                  ConsoleButton(
                    onPressed: remote.connecting
                        ? null
                        : () => remote.connect(address, code),
                    child: Text(remote.connecting ? 'Connecting…' : 'Connect'),
                  ),
                  const SizedBox(height: 12),
                  button('Find nearby hosts', remote.discover),
                  if (remote.discoveryError != null)
                    Text(remote.discoveryError!),
                  const Text(
                    'Use a trusted local network. This preview sends controller and screen data over an unencrypted LAN connection.',
                  ),
                ],
                if (remote.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    remote.error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ],
                const SizedBox(height: 20),
                if (page != 'choose')
                  button('Back', () => setState(() => page = 'choose')),
              ],
            ),
          ),
        ),
      );
    },
  );
}
