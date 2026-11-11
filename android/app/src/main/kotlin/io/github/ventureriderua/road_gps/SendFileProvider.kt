package io.github.ventureriderua.road_gps

import androidx.core.content.FileProvider

// Власний клас, щоб не зіткнутися в маніфесті з FileProvider інших бібліотек.
class SendFileProvider : FileProvider()
