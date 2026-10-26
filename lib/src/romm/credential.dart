/// Reusable RomM authentication, never the user's password. OAuth access tokens
/// remain in memory; a restored OAuth session obtains one using its refresh token.
class RommCredential {
  const RommCredential(this.kind, this.secret);
  factory RommCredential.fromJson(Map j) {
    final kind = j['kind'], secret = j['secret'];
    if (!['refresh', 'client'].contains(kind) ||
        secret is! String ||
        secret.isEmpty ||
        secret.length > 16384 ||
        secret.contains(RegExp(r'[\x00-\x20]')) ||
        (kind == 'client' &&
            !RegExp(r'^rmm_[a-fA-F0-9]{64}$').hasMatch(secret))) {
      throw const FormatException('Invalid saved RomM sign-in');
    }
    return RommCredential(kind as String, secret);
  }
  final String kind, secret;
  Map<String, dynamic> toJson() => {'kind': kind, 'secret': secret};
  @override
  String toString() => 'RommCredential($kind, redacted)';
}
