package com.vscodroid

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class InputPreviewWiringTest {

    @Test
    fun `preview reads the EditContext text used by the editor`() {
        val source = SourceScan.withoutComments(
            SourceScan.read("src/main/kotlin/com/vscodroid/MainActivity.kt")
        )
        val start = source.indexOf("private const val INPUT_PREVIEW_SCRIPT")
        assertTrue(start >= 0, "the input preview script is missing")
        val end = source.indexOf("class MainActivity", start)
        assertTrue(end > start, "the input preview script has no end")
        val script = source.substring(start, end)
        assertTrue(script.contains("element.editContext"), "the preview does not read EditContext")
        val editContext = script.indexOf("if (element.editContext)")
        val contentEditable = script.indexOf("if (element.isContentEditable)")
        assertTrue(
            editContext >= 0 && editContext < contentEditable,
            "the preview must prefer EditContext text over the rendered DOM text",
        )
        assertTrue(
            script.contains("element.editContext.text"),
            "the preview does not read the editor's current text",
        )
    }
}
