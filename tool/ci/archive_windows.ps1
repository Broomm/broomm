$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $env:BROOMM_ARCHIVE_SOURCE, $env:BROOMM_ARCHIVE_OUTPUT,
    [System.IO.Compression.CompressionLevel]::Optimal, $false)
$archive = [System.IO.Compression.ZipFile]::OpenRead($env:BROOMM_ARCHIVE_OUTPUT)
try {
    if ($archive.Entries.Count -eq 0) { throw 'Empty Windows archive' }
    foreach ($entry in $archive.Entries) {
        if ($entry.Name -ne '') {
            $stream = $entry.Open()
            try { $stream.CopyTo([System.IO.Stream]::Null) } finally { $stream.Dispose() }
        }
    }
} finally { $archive.Dispose() }
