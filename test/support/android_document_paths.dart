/// Model Android DocumentsProvider paths from host fixture files. URI segments
/// remove host separators while retaining literal document names. This belongs
/// only in the fake provider: production must reject malformed transport paths.
String androidDocumentRelativePath(Uri directory, Uri entry) {
  final base = directory.pathSegments.where((s) => s.isNotEmpty).toList();
  final parts = entry.pathSegments.where((s) => s.isNotEmpty).toList();
  if (directory.scheme != 'file' ||
      entry.scheme != 'file' ||
      directory.authority != entry.authority ||
      parts.length <= base.length ||
      Iterable<int>.generate(base.length).any((i) => base[i] != parts[i])) {
    throw ArgumentError('Fixture entry is outside its document directory');
  }
  return parts.skip(base.length).join('/');
}
