package com.tuyenmai.openkey.core

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

class BilingualAutoSwitchTest {

    @BeforeEach
    fun setUp() {
        VietnameseEngine.initEngine()
        VietnameseEngine.resetSession()
        VietnameseEngine.syncConfig(
            language = 1,
            inputType = 0, // Telex
            checkSpelling = 1,
            useModernOrthography = 1,
            restoreIfWrongSpelling = 1,
            fixRecommendBrowser = 1,
            useSmartSwitchKey = 1
        )
    }

    class VirtualScreen(var text: String = "") {
        init {
            VietnameseEngine.resetSession()
        }

        fun typeASCII(s: String): List<HookSnapshot> {
            val snapshots = mutableListOf<HookSnapshot>()
            for (ch in s) {
                snapshots.add(typeChar(ch))
            }
            return snapshots
        }

        fun typeKey(keyCode: Int, caps: Int = 0, isOtherControl: Boolean = false): HookSnapshot {
            val snap = VietnameseEngine.handleKeyEvent(keyCode, caps, isOtherControl)
            applySnapshot(snap, keyCode, caps)
            return snap
        }

        fun typeChar(ch: Char): HookSnapshot {
            val mapping = VietnameseData.charToKeyCode(ch)
            val keyCode = mapping.first
            val caps = mapping.second
            val snap = VietnameseEngine.handleKeyEvent(keyCode, caps, false)
            applySnapshot(snap, keyCode, caps, ch)
            return snap
        }

        private fun applySnapshot(snap: HookSnapshot, keyCode: Int, caps: Int, fallbackChar: Char? = null) {
            if (snap.code == HookCodeState.WILL_PROCESS ||
                snap.code == HookCodeState.RESTORE ||
                snap.code == HookCodeState.RESTORE_AND_START_NEW_SESSION
            ) {
                val bs = snap.backspaceCount
                if (bs > 0) {
                    val toRemove = bs.coerceAtMost(text.length)
                    text = text.dropLast(toRemove)
                }
                text += snap.decodedString
            } else {
                if (keyCode == VietnameseData.KEY_DELETE.toInt()) {
                    if (text.isNotEmpty()) {
                        text = text.dropLast(1)
                    }
                } else if (fallbackChar != null) {
                    text += fallbackChar
                } else {
                    val c = VietnameseData.keyCodeToCharacter(
                        keyCode.toUInt() or (if (caps != 0) VietnameseData.CAPS_MASK else 0u)
                    )
                    if (c != 0.toUShort()) {
                        text += c.toInt().toChar()
                    }
                }
            }
        }
    }

    // 1. droppedKeys reconstruction for English words with doubled Telex modifier letters (REQ-003)
    @Test
    fun testDroppedKeysReconstructionForDoubledTelexEnglishWords() {
        val doubledModifierWords = listOf(
            "cheese ", "seemed ", "needed ", "deepseek ", "google ", "choose ",
            "process ", "success ", "message ", "issue ", "office ", "coffee ",
            "error ", "array ", "current ", "correct ", "tomorrow ", "sorry ",
            "address ", "middle ", "reddit "
        )

        for (word in doubledModifierWords) {
            val screen = VirtualScreen()
            screen.typeASCII(word)
            assertEquals(word, screen.text, "Typing '$word' must restore raw English word without Telex corruption")
        }
    }

    // 2. Doubled-tone escape repair while preserving true double-letter English words (REQ-003)
    @Test
    fun testDoubledToneEscapeRepairAndDoubleLetterPreservation() {
        val repairCases = listOf(
            "mixx " to "mix ",
            "fixx " to "fix ",
            "boxx " to "box "
        )
        for ((input, expected) in repairCases) {
            val screen = VirtualScreen()
            screen.typeASCII(input)
            assertEquals(expected, screen.text, "Escape sequence '$input' must collapse to '$expected'")
        }

        val trueDoubleLetterWords = listOf(
            "boss ", "class ", "pass "
        )
        for (word in trueDoubleLetterWords) {
            val screen = VirtualScreen()
            screen.typeASCII(word)
            assertEquals(word, screen.text, "True double-letter English word '$word' must retain both letters")
        }
    }

    // 3. Standalone English/developer collision words restored in mixed sentences while genuine Vietnamese words remain (REQ-003)
    @Test
    fun testStandaloneEnglishCollisionsAndMixedSentences() {
        val collisionWords = listOf(
            "test ", "list ", "this ", "best ", "more ", "core ", "view ", "show ", "flow ",
            "user ", "vars ", "chars ", "docs ", "work ", "word ", "tree ", "free ", "see ",
            "too ", "add ", "mix ", "fix ", "box "
        )
        for (w in collisionWords) {
            val screen = VirtualScreen()
            screen.typeASCII(w)
            assertEquals(w, screen.text, "Collision word '$w' must restore to English on word break")
        }

        // Mixed sentences
        val screenSentence1 = VirtualScreen()
        screenSentence1.typeASCII("anh đang test cái list này ")
        assertEquals("anh đang test cái list này ", screenSentence1.text)

        val screenSentence2 = VirtualScreen()
        screenSentence2.typeASCII("mình dùng deepseek và google ở office ")
        assertEquals("mình dùng deepseek và google ở office ", screenSentence2.text)

        // Genuine Vietnamese words must NOT be restored to English
        val vietnameseWords = listOf(
            "có ", "bạn ", "anh ", "ăn ", "ở ", "ạ "
        )
        for (vw in vietnameseWords) {
            val screenVn = VirtualScreen()
            screenVn.typeASCII(vw)
            assertEquals(vw, screenVn.text, "Genuine Vietnamese word '$vw' must remain Vietnamese")
        }
    }

    // 4. 1-2 word English phrase look-back restoration (REQ-003)
    @Test
    fun testTwoWordLookbackRestoration() {
        val lookbackPhrases = listOf(
            "is good " to "is good ",
            "in case " to "in case ",
            "for sure " to "for sure ",
            "of course " to "of course ",
            "it is good for sure " to "it is good for sure "
        )
        for ((input, expected) in lookbackPhrases) {
            val screen = VirtualScreen()
            screen.typeASCII(input)
            assertEquals(expected, screen.text, "Lookback phrase '$input' must produce '$expected'")
        }
    }

    // 5. Contractions, hyphenated w- words, and multi-capital acronyms (REQ-003)
    @Test
    fun testContractionsHyphensAndAcronyms() {
        // Contractions
        val screenDoesn = VirtualScreen()
        screenDoesn.typeASCII("doesn't ")
        assertEquals("doesn't ", screenDoesn.text, "Contraction doesn't must be preserved")

        val screenIsnt = VirtualScreen()
        screenIsnt.typeASCII("isn't ")
        assertEquals("isn't ", screenIsnt.text, "Contraction isn't must be preserved")

        // Hyphenated w- words
        val screenWifi = VirtualScreen()
        screenWifi.typeASCII("Wi-Fi ")
        assertEquals("Wi-Fi ", screenWifi.text, "Hyphenated word Wi-Fi must be preserved")

        // Multi-capital acronyms
        val screenNas = VirtualScreen()
        screenNas.typeASCII("NAS ")
        assertEquals("NAS ", screenNas.text, "Acronym NAS must be preserved")

        val screenGoPro = VirtualScreen()
        screenGoPro.typeASCII("GoPro ")
        assertEquals("GoPro ", screenGoPro.text, "Brand GoPro must be preserved")

        // Vietnamese Đ-acronyms must NEVER be restored to ASCII
        val screenVdv = VirtualScreen()
        screenVdv.typeASCII("VĐV ")
        assertEquals("VĐV ", screenVdv.text, "Vietnamese acronym VĐV must be preserved")

        val screenBds = VirtualScreen()
        screenBds.typeASCII("BĐS ")
        assertEquals("BĐS ", screenBds.text, "Vietnamese acronym BĐS must be preserved")
    }

    // 6. Context-Ordered V / E Homograph Disambiguation (REQ-018, ADR-019)
    @Test
    fun testContextOrderedHomographDisambiguation() {
        // (a) V (VIETNAMESE_FIRST) context preserves composed Vietnamese words
        val vietnameseFirstCases = listOf(
            "sex " to "sẽ ",
            "anh sex lamf " to "anh sẽ làm ",
            "max nguoonf " to "mã nguồn ",
            "bacs six " to "bác sĩ ",
            "banr vex " to "bản vẽ "
        )
        for ((input, expected) in vietnameseFirstCases) {
            val screen = VirtualScreen()
            screen.typeASCII(input)
            assertEquals(expected, screen.text, "VIETNAMESE_FIRST context for '$input' must produce '$expected'")
        }

        // (b) E (ENGLISH_FIRST) context restores English words
        val englishFirstCases = listOf(
            "have sex " to "have sex ",
            "at max " to "at max ",
            "number six " to "number six ",
            "income tax " to "income tax ",
            "full moon " to "full moon "
        )
        for ((input, expected) in englishFirstCases) {
            val screen = VirtualScreen()
            screen.typeASCII(input)
            assertEquals(expected, screen.text, "ENGLISH_FIRST context for '$input' must produce '$expected'")
        }

        // (c) 2-word look-back restores English homographs
        val lookbackCases = listOf(
            "sex is " to "sex is ",
            "max value " to "max value ",
            "tax rate " to "tax rate "
        )
        for ((input, expected) in lookbackCases) {
            val screen = VirtualScreen()
            screen.typeASCII(input)
            assertEquals(expected, screen.text, "Lookback restoration for '$input' must produce '$expected'")
        }
    }

    // 7. Vietnamese syllable protection ('thể' vs 'there') and Standalone-W escape ('Why' vs 'Wwhy') (REQ-019, ADR-020)
    @Test
    fun testVietnameseSyllableProtectionAndStandaloneWEscape() {
        // (a) 'theer ' -> 'thể ', 'there ' -> 'thể ', 'cos theer ' -> 'có thể ', 'cos there ' -> 'có thể ', 'con theer ' -> 'con thể ', 'con there ' -> 'con thể ', 'hay theer ' -> 'hay thể ', 'nhuw thees ' -> 'như thế ', 'nhuw these ' -> 'như thế ', 'thees ' -> 'thế ', 'these ' -> 'thế '
        val vietnameseSyllables = listOf(
            "theer " to "thể ",
            "there " to "thể ",
            "cos theer " to "có thể ",
            "cos there " to "có thể ",
            "con theer " to "con thể ",
            "con there " to "con thể ",
            "hay theer " to "hay thể ",
            "nhuw thees " to "như thế ",
            "nhuw these " to "như thế ",
            "thees " to "thế ",
            "these " to "thế "
        )
        for ((input, expected) in vietnameseSyllables) {
            val screen = VirtualScreen()
            screen.typeASCII(input)
            assertEquals(expected, screen.text, "Typing '$input' must produce '$expected'")
        }

        // (b) English phrases 'there is ' -> 'there is ', 'there are ' -> 'there are ', 'over there ' -> 'over there ', 'these are ' -> 'these are '
        val englishPhrases = listOf(
            "there is " to "there is ",
            "there are " to "there are ",
            "over there " to "over there ",
            "these are " to "these are "
        )
        for ((input, expected) in englishPhrases) {
            val screen = VirtualScreen()
            screen.typeASCII(input)
            assertEquals(expected, screen.text, "Typing '$input' must produce '$expected'")
        }

        // (c) Standalone-W escape and capitalization: 'Why ' -> 'Why ', 'Wwhy ' -> 'Why ', 'why ' -> 'why ', 'wwhy ' -> 'why ', and with AutoWordingEngine.shared.syncConfig(isEnabled = true, grammarRepair = true, shorthandExpansion = true, candidateSuggestions = true, doubleSpacePeriod = true), typing 'cos there. wwhy also wrong ' -> 'có thể. Why also wrong ' and 'cos theer. Wwhy also wrong ' -> 'có thể. Why also wrong '.
        val wEscapeCases = listOf(
            "Why " to "Why ",
            "Wwhy " to "Why ",
            "why " to "why ",
            "wwhy " to "why "
        )
        for ((input, expected) in wEscapeCases) {
            val screen = VirtualScreen()
            screen.typeASCII(input)
            assertEquals(expected, screen.text, "Typing '$input' must produce '$expected'")
        }

        AutoWordingEngine.shared.syncConfig(
            isEnabled = true,
            grammarRepair = true,
            shorthandExpansion = true,
            candidateSuggestions = true,
            doubleSpacePeriod = true
        )
        try {
            val screen1 = VirtualScreen()
            screen1.typeASCII("cos there. wwhy also wrong ")
            assertEquals("có thể. Why also wrong ", screen1.text)

            val screen2 = VirtualScreen()
            screen2.typeASCII("cos theer. Wwhy also wrong ")
            assertEquals("có thể. Why also wrong ", screen2.text)
        } finally {
            AutoWordingEngine.shared.syncConfig(
                isEnabled = false,
                grammarRepair = false,
                shorthandExpansion = false,
                candidateSuggestions = false,
                doubleSpacePeriod = false
            )
        }
    }
}
