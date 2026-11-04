/// Reads the native loader's title observation without joining independent
/// stdout/stderr pipes. Both pipes can split a line at arbitrary byte offsets.
class SwitchLaunchIdentity {
  SwitchLaunchIdentity(String emulator)
    : _pattern = emulator == 'Eden'
          ? RegExp(r'Core .*Loading [^\r\n]*\((010[0-9a-fA-F]{13})\) \.\.\.')
          : RegExp(
              r'Loader Start: Application Loaded: [^\r\n]*\[(010[0-9a-fA-F]{13})\] \[64-bit\]',
            );

  final RegExp _pattern;
  final _pipes = ['', ''];
  String? program;

  void add(List<int> bytes, {required bool stderr}) {
    if (program != null) return;
    final pipe = stderr ? 1 : 0;
    // Consume every byte of large bursts, retaining a bounded overlap for a
    // loader record that straddles chunks. IDs/record syntax are ASCII.
    for (var start = 0; start < bytes.length; start += 8192) {
      final end = start + 8192 < bytes.length ? start + 8192 : bytes.length;
      final text =
          _pipes[pipe] + String.fromCharCodes(bytes.sublist(start, end));
      final match = _pattern.firstMatch(text);
      if (match != null) {
        program = match[1]!.toLowerCase();
        _pipes.fillRange(0, _pipes.length, '');
        return;
      }
      _pipes[pipe] = text.length > 32768
          ? text.substring(text.length - 32768)
          : text;
    }
  }
}
