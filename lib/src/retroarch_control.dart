/// The network PAUSE_TOGGLE command must be tied to a Broomm transition.
/// A later native pause is an observation, not another request to resume.
class RetroArchPauseControl {
  RetroArchPauseControl({
    required this.query,
    required this.toggle,
    required this.matches,
    required this.current,
  });

  final Future<String?> Function() query;
  final void Function() toggle;
  final bool Function(String) matches;
  final bool Function() current;
  bool _busy = false, _wanted = true, _resumePending = false;
  bool? _requested;
  int _release = 0, _seenRelease = 0, _revision = -1;

  Future<int?> update({
    required bool blocked,
    required int releaseSerial,
    required int revision,
  }) async {
    if (_wanted != blocked || _revision != revision) _requested = null;
    _wanted = blocked;
    _revision = revision;
    _release = releaseSerial;
    if (blocked) _resumePending = false;
    if (_busy || !current()) return null;
    _busy = true;
    try {
      final reply = await query();
      if (!current() || reply == null || !matches(reply)) return null;
      final paused = reply.startsWith('GET_STATUS PAUSED ');
      if (!_wanted && _release != _seenRelease) {
        _seenRelease = _release;
        _resumePending = true;
        _requested = null;
      }
      if (paused == _wanted) {
        _requested = null;
        if (!_wanted) _resumePending = false;
        return paused ? 1 : 0;
      }
      if ((!_wanted && !_resumePending) || _requested == _wanted) {
        return paused ? 1 : 0;
      }
      _requested = _wanted;
      toggle();
      final after = await query();
      if (!current() || after == null || !matches(after)) return null;
      final nowPaused = after.startsWith('GET_STATUS PAUSED ');
      if (nowPaused == _wanted) {
        _requested = null;
        if (!_wanted) _resumePending = false;
      }
      return nowPaused ? 1 : 0;
    } finally {
      _busy = false;
    }
  }
}
