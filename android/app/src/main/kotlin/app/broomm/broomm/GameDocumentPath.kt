package app.broomm.broomm

/** The document alias carries the same token/file capability as /game; never a folder grant. */
internal data class GameGrantPath(val token: String, val relative: List<String>) {
    val documentId: String get() = "$token:${relative.joinToString("/")}"
}

internal fun gameGrantPath(segments: List<String>): GameGrantPath {
    val document = segments.firstOrNull() == "document"
    val token: String
    val relative: List<String>
    if (document) {
        require(segments.size == 2)
        val parts = segments[1].split(':', limit = 2)
        require(parts.size == 2)
        token = parts[0]; relative = parts[1].split('/')
    } else {
        require(segments.size in 3..35 && segments[0] == "game")
        token = segments[1]; relative = segments.drop(2)
    }
    require(Regex("[a-f0-9]{32}").matches(token) && relative.size in 1..33 &&
        relative.none { it.isEmpty() || it == "." || it == ".." || '\\' in it || '/' in it || '\u0000' in it })
    if (document) require(relative.none { part -> part.any { it.code < 32 || it.code == 127 } } &&
        relative.joinToString("/").toByteArray(Charsets.UTF_8).size <= 4096)
    return GameGrantPath(token, relative)
}

