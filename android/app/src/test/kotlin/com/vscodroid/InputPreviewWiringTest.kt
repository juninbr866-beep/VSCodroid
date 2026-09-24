package com.vscodroid

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class InputPreviewWiringTest {

    @Test
    fun `preview follows all editor input paths`() {
        val source = SourceScan.withoutComments(
            SourceScan.read("src/main/kotlin/com/vscodroid/MainActivity.kt")
        )
        val start = source.indexOf("private const val INPUT_PREVIEW_SCRIPT")
        assertTrue(start >= 0, "the input preview script is missing")
        val end = source.indexOf("class MainActivity", start)
        assertTrue(end > start, "the input preview script has no end")
        val script = source.substring(start, end)
        val editContext = script.indexOf("if (host.editContext)")
        val contentEditable = script.indexOf("if (host.isContentEditable)")
        assertTrue(editContext >= 0 && editContext < contentEditable, "EditContext must be read first")
        for (name in listOf(
            "host.editContext.text",
            ".native-edit-context",
            ".monaco-editor textarea.inputarea",
            ".xterm-helper-textarea",
            "textupdate",
            "textformatupdate",
            "beforeinput",
            "input",
            "keydown",
            "focusin",
            "selectionchange",
        )) {
            assertTrue(script.contains(name), "the preview does not handle $name")
        }
        assertTrue(source.contains("inputPreviewGeneration"), "stale preview callbacks are not invalidated")
    }
}
