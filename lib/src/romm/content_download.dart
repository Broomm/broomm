import 'dart:async';
import 'dart:io';

import 'models.dart';
import 'transfer.dart';

/// One bounded HTTP response into an already owned private destination. Token
/// refresh, library locks and publication belong to the calling workflows.
Future<void> downloadRommContent(
  HttpClient http,
  Uri uri,
  String access,
  int expectedBytes,
  File destination, {
  required Duration deadline,
  required DownloadCancellation cancellation,
  required void Function(int) onProgress,
  bool Function()? isClosed,
  void Function(bool)? writerState,
}) async {
  HttpClientRequest? request;
  RandomAccessFile? output;
  var stopped = false;
  final totalDeadline = Timer(
    const Duration(hours: 24),
    () => request?.abort(),
  );
  cancellation.abort = () => request?.abort();
  try {
    cancellation.check();
    request = await http
        .getUrl(uri)
        .then((value) {
          if (stopped || cancellation.cancelled || (isClosed?.call() ?? false))
            value.abort();
          return value;
        })
        .timeout(deadline);
    cancellation.check();
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $access');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close().timeout(deadline);
    if (response.statusCode != 200) {
      throw RommFailure(switch (response.statusCode) {
        401 => 'Your session expired. Sign in again to download.',
        403 => 'This account does not have permission to download this game.',
        404 =>
          'This game file is no longer available in RomM. Refresh and retry.',
        >= 300 && < 400 => 'RomM redirected the download. Credentials were not forwarded. Use the final server address.',
        _ =>
          'RomM could not download this file (HTTP ${response.statusCode}). Retry from the game page.',
      }, status: response.statusCode);
    }
    if (response.contentLength >= 0 &&
        response.contentLength != expectedBytes) {
      throw const RommFailure(
        'The file size changed in RomM. Refresh the game and retry.',
      );
    }
    output = await destination.open(mode: FileMode.writeOnly);
    writerState?.call(true);
    var received = 0;
    await for (final chunk in response.timeout(deadline)) {
      cancellation.check();
      received += chunk.length;
      if (received > expectedBytes)
        throw const RommFailure(
          'RomM sent more data than the file manifest allows.',
        );
      await output.writeFrom(chunk);
      onProgress(received);
    }
    cancellation.check();
    if (received != expectedBytes)
      throw const RommFailure(
        'The download ended before the whole file arrived. Please retry.',
      );
    await output.flush();
  } on RommFailure {
    rethrow;
  } on TimeoutException {
    throw const RommFailure(
      'The download stalled. Check your connection and retry.',
    );
  } on IOException {
    cancellation.check();
    throw const RommFailure(
      'The download failed. Check your connection, free disk space and write access, then retry.',
    );
  } finally {
    stopped = true;
    totalDeadline.cancel();
    cancellation.abort = null;
    request?.abort();
    await output?.close();
    writerState?.call(false);
  }
}
