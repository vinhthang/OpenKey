package com.tuyenmai.openkey.core

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

enum class CandidateKind {
    CORRECTION,
    STEM_COMPLETION,
    NEXT_WORD
}

data class WordCandidate(
    val id: Int,
    val text: String,
    val kind: CandidateKind,
    val replaceLength: Int
)

class AutoWordingEngine private constructor() {
    companion object {
        val shared = AutoWordingEngine()

        fun extractVowelModifiers(text: String): Set<Char> {
            val mods = mutableSetOf<Char>()
            for (ch in text.lowercase()) {
                when (ch) {
                    'ă', 'ắ', 'ằ', 'ẳ', 'ẵ', 'ặ' -> mods.add('ă')
                    'â', 'ấ', 'ầ', 'ẩ', 'ẫ', 'ậ' -> mods.add('â')
                    'ê', 'ế', 'ề', 'ể', 'ễ', 'ệ' -> mods.add('ê')
                    'ô', 'ố', 'ồ', 'ổ', 'ỗ', 'ộ' -> mods.add('ô')
                    'ơ', 'ớ', 'ờ', 'ở', 'ỡ', 'ợ' -> mods.add('ơ')
                    'ư', 'ứ', 'ừ', 'ử', 'ữ', 'ự' -> mods.add('ư')
                    'đ' -> mods.add('đ')
                }
            }
            return mods
        }
    }

    private val lock = ReentrantLock()

    var asyncCandidateExecutionEnabled: Boolean = false
    private val candidateGeneration = java.util.concurrent.atomic.AtomicLong(0L)
    val currentGenerationId: Long get() = candidateGeneration.get()
    fun nextGenerationId(): Long = candidateGeneration.incrementAndGet()

    private val candidateWorker = java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "openkey-candidate-worker").apply { isDaemon = true }
    }

    fun submitCandidateTaskForGeneration(generationId: Long, computeBlock: () -> List<WordCandidate>) {
        if (generationId != candidateGeneration.get()) {
            return
        }
        if (asyncCandidateExecutionEnabled) {
            candidateWorker.execute {
                if (generationId != candidateGeneration.get()) {
                    return@execute
                }
                val candidates = computeBlock()
                if (generationId == candidateGeneration.get()) {
                    updateCandidates(candidates)
                }
            }
        } else {
            val candidates = computeBlock()
            if (generationId == candidateGeneration.get()) {
                updateCandidates(candidates)
            }
        }
    }

    var isEnabled: Boolean
        get() = lock.withLock { _isEnabled }
        set(value) {
            lock.withLock { _isEnabled = value }
            if (!value) clearCandidates()
        }
    private var _isEnabled: Boolean = false

    var grammarRepairEnabled: Boolean
        get() = lock.withLock { _grammarRepairEnabled }
        set(value) { lock.withLock { _grammarRepairEnabled = value } }
    private var _grammarRepairEnabled: Boolean = false

    var shorthandExpansionEnabled: Boolean
        get() = lock.withLock { _shorthandExpansionEnabled }
        set(value) { lock.withLock { _shorthandExpansionEnabled = value } }
    private var _shorthandExpansionEnabled: Boolean = false

    var candidateSuggestionsEnabled: Boolean
        get() = lock.withLock { _candidateSuggestionsEnabled }
        set(value) {
            lock.withLock { _candidateSuggestionsEnabled = value }
            if (!value) clearCandidates()
        }
    private var _candidateSuggestionsEnabled: Boolean = false

    var doubleSpacePeriodEnabled: Boolean
        get() = lock.withLock { _doubleSpacePeriodEnabled }
        set(value) { lock.withLock { _doubleSpacePeriodEnabled = value } }
    private var _doubleSpacePeriodEnabled: Boolean = false

    fun syncConfig(
        isEnabled: Boolean,
        grammarRepair: Boolean,
        shorthandExpansion: Boolean,
        candidateSuggestions: Boolean,
        doubleSpacePeriod: Boolean = false
    ) {
        lock.withLock {
            this._isEnabled = isEnabled
            this._grammarRepairEnabled = grammarRepair
            this._shorthandExpansionEnabled = shorthandExpansion
            this._candidateSuggestionsEnabled = candidateSuggestions
            this._doubleSpacePeriodEnabled = doubleSpacePeriod
        }
        if (!isEnabled || !candidateSuggestions) clearCandidates()
    }

    var customShorthands: MutableMap<String, String>
        get() = lock.withLock { _customShorthands.toMutableMap() }
        set(value) { lock.withLock { _customShorthands = value.toMutableMap() } }
    private var _customShorthands: MutableMap<String, String> = mutableMapOf()

    val userFrequencies: Map<String, Int>
        get() = lock.withLock { _userFrequencies.toMap() }
    private val _userFrequencies: MutableMap<String, Int> = mutableMapOf()

    val activeCandidates: List<WordCandidate>
        get() = lock.withLock { _activeCandidates.toList() }
    private var _activeCandidates: List<WordCandidate> = emptyList()

    var onCandidatesChanged: ((List<WordCandidate>) -> Unit)? = null

    fun recordCandidateAcceptance(text: String) {
        val clean = text.trim().lowercase()
        if (clean.isEmpty()) return
        lock.withLock {
            _userFrequencies[clean] = (_userFrequencies[clean] ?: 0) + 1
        }
    }

    fun resetLearnedFrequencies() {
        lock.withLock { _userFrequencies.clear() }
    }

    fun updateCandidates(candidates: List<WordCandidate>) {
        lock.withLock {
            if (_activeCandidates == candidates) return
            _activeCandidates = candidates
        }
        onCandidatesChanged?.invoke(candidates)
    }

    fun clearCandidates() {
        updateCandidates(emptyList())
    }

    fun expandShorthand(rawWord: String): String? {
        if (!isEnabled || !shorthandExpansionEnabled) return null
        if (rawWord.isEmpty()) return null

        val lower = rawWord.lowercase()
        val baseExpansion = lock.withLock { _customShorthands[lower] } ?: return null

        val isAllCaps = rawWord.length > 1 && rawWord.all { it.isUpperCase() }
        if (isAllCaps) {
            return baseExpansion.uppercase()
        }

        if (rawWord.first().isUpperCase()) {
            return baseExpansion.replaceFirstChar { it.uppercase() }
        }

        return baseExpansion
    }

    fun computeCurrentWordCandidates(
        rawStem: String,
        currentSyllable: String,
        isWrongSpelling: Boolean = false,
        languagePriority: LanguagePriority = LanguagePriority.VIETNAMESE_FIRST
    ): List<WordCandidate> {
        if (!isEnabled || !candidateSuggestionsEnabled) return emptyList()
        if (rawStem.isEmpty() && currentSyllable.isEmpty()) return emptyList()

        val dict = VietnameseDictionary.shared
        if (isWrongSpelling && dict.keepWords.contains(rawStem.lowercase())) {
            return emptyList()
        }

        val results = mutableListOf<String>()

        // 1. Unaccented stem lookup
        val stemSource = if (currentSyllable.isEmpty()) rawStem else currentSyllable
        val cleanStem = VietnameseDictionary.stripVietnameseDiacritics(stemSource).lowercase()
        val stemMatches = dict.stemToWords[cleanStem] ?: emptyList()
        for (m in stemMatches) {
            if (!results.contains(m)) results.add(m)
        }

        // 2. Transposition signature lookup
        val stemOnset = VietnameseDictionary.extractVietnameseOnset(cleanStem)
        val cleanRaw = rawStem.lowercase()
        val rawSig = cleanRaw.toCharArray().sorted().joinToString("")
        dict.telexSignatureToWords[rawSig]?.let { matches ->
            for (m in matches) {
                if (results.size >= 8) break
                val mOnset = VietnameseDictionary.extractVietnameseOnset(VietnameseDictionary.stripVietnameseDiacritics(m))
                if (!results.contains(m) && (stemOnset.isEmpty() || mOnset == stemOnset)) {
                    results.add(m)
                }
            }
        }

        // Strip trailing tone key if transposed
        if (results.size < 8 && cleanRaw.length > 2) {
            val tones = setOf('s', 'f', 'r', 'x', 'j', 'w', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0')
            if (tones.contains(cleanRaw.last())) {
                val trimmed = cleanRaw.dropLast(1)
                val trimmedSig = trimmed.toCharArray().sorted().joinToString("")
                dict.telexSignatureToWords[trimmedSig]?.let { matches ->
                    for (m in matches) {
                        if (results.size >= 8) break
                        val mOnset = VietnameseDictionary.extractVietnameseOnset(VietnameseDictionary.stripVietnameseDiacritics(m))
                        if (!results.contains(m) && (stemOnset.isEmpty() || mOnset == stemOnset)) {
                            results.add(m)
                        }
                    }
                }
            }
        }

        // Boost ranking with user frequencies
        val freqs = lock.withLock { _userFrequencies.toMap() }
        val sortedByFreq = if (freqs.isEmpty()) {
            results
        } else {
            results.sortedByDescending { freqs[it.lowercase()] ?: 0 }
        }

        // Prioritize candidates preserving vowel modifiers present in currentSyllable
        val requiredModifiers = extractVowelModifiers(currentSyllable)
        val modifierRanked = if (requiredModifiers.isEmpty()) {
            sortedByFreq
        } else {
            val matching = sortedByFreq.filter { requiredModifiers.all { mod -> extractVowelModifiers(it).contains(mod) } }
            val nonMatching = sortedByFreq.filter { !requiredModifiers.all { mod -> extractVowelModifiers(it).contains(mod) } }
            matching + nonMatching
        }

        // Place candidates strictly equal to currentSyllable.lowercase() after distinct accented candidates
        val currentLower = currentSyllable.lowercase()
        val distinctAccented = mutableListOf<String>()
        val exactMatches = mutableListOf<String>()
        for (w in modifierRanked) {
            if (currentLower.isNotEmpty() && w.lowercase() == currentLower) {
                exactMatches.add(w)
            } else {
                distinctAccented.add(w)
            }
        }
        val vietnameseSorted = distinctAccented + exactMatches

        val engCandidates = dict.computeEnglishCandidates(rawStem)
        val combinedTexts = mutableListOf<String>()

        if (languagePriority == LanguagePriority.ENGLISH_FIRST) {
            for (eng in engCandidates) if (!combinedTexts.contains(eng)) combinedTexts.add(eng)
            for (vn in vietnameseSorted) if (!combinedTexts.contains(vn)) combinedTexts.add(vn)
        } else {
            for (vn in vietnameseSorted.take(2)) if (!combinedTexts.contains(vn)) combinedTexts.add(vn)
            for (eng in engCandidates) if (!combinedTexts.contains(eng)) combinedTexts.add(eng)
            for (vn in vietnameseSorted.drop(2)) if (!combinedTexts.contains(vn)) combinedTexts.add(vn)
        }

        if (combinedTexts.isEmpty()) return emptyList()

        val replaceLen = if (currentSyllable.isEmpty()) rawStem.length else currentSyllable.length
        return combinedTexts.take(3).mapIndexed { idx, text ->
            val isEng = engCandidates.contains(text)
            val kind = when {
                isEng -> CandidateKind.CORRECTION
                isWrongSpelling -> CandidateKind.CORRECTION
                stemMatches.contains(text) -> CandidateKind.STEM_COMPLETION
                else -> CandidateKind.CORRECTION
            }
            WordCandidate(id = idx, text = text, kind = kind, replaceLength = replaceLen)
        }
    }

    fun computeNextWordCandidates(previousWord: String): List<WordCandidate> {
        if (!isEnabled || !candidateSuggestionsEnabled) return emptyList()
        val cleanPrev = previousWord.trim().lowercase()
        if (cleanPrev.isEmpty()) return emptyList()

        val dict = VietnameseDictionary.shared
        val continuations = dict.compoundBigrams[cleanPrev] ?: return emptyList()
        if (continuations.isEmpty()) return emptyList()

        val pool = continuations.take(8)
        val freqs = lock.withLock { _userFrequencies.toMap() }
        val sortedPool = if (freqs.isEmpty()) {
            pool
        } else {
            pool.sortedByDescending { freqs[it.lowercase()] ?: 0 }
        }

        return sortedPool.take(3).mapIndexed { idx, continuation ->
            WordCandidate(id = idx, text = continuation, kind = CandidateKind.NEXT_WORD, replaceLength = 0)
        }
    }

    fun repairPhonotacticCluster(
        typingWord: UIntArray,
        index: Int,
        vowelStartIndex: Int,
        vowelEndIndex: Int,
        vowelCount: Int,
        isInsertingMark: Boolean
    ): Boolean {
        if (!isEnabled || !grammarRepairEnabled) return false
        var repaired = false
        val vsi = vowelStartIndex
        val vei = vowelEndIndex

        fun charAt(idx: Int): UShort = (typingWord[idx] and 0xFFFFu).toUShort()

        val hasFinalConsonant = (index - 1 > vei) && VietnameseData.isConsonant(charAt(vei + 1))
        if (!hasFinalConsonant) return false

        // Rule 1: ie/ye + final consonant -> iê/yê
        if (vei >= 1) {
            val prev = charAt(vei - 1)
            val curr = charAt(vei)
            if ((prev == KEY_I || prev == KEY_Y) && curr == KEY_E) {
                val prevIdx = vei - 1
                val currIdx = vei
                val hasToneOrInserting = isInsertingMark ||
                        (typingWord[prevIdx] and MARK_MASK) != 0u ||
                        (typingWord[currIdx] and MARK_MASK) != 0u
                if (hasToneOrInserting && (typingWord[vei] and TONE_MASK) == 0u) {
                    typingWord[vei] = typingWord[vei] or (TONE_MASK or AUTO_TONE_MASK)
                    repaired = true
                }
            }
        }

        // Rule 2: uow -> ươ
        if (vei >= vsi + 1) {
            for (i in vsi until vei) {
                val c1 = charAt(i)
                val c2 = charAt(i + 1)
                if (c1 == KEY_U && c2 == KEY_O) {
                    if (i > 0 && charAt(i - 1) == KEY_Q) continue
                    val m1 = typingWord[i] and TONEW_MASK
                    val m2 = typingWord[i + 1] and TONEW_MASK
                    if ((m1 != 0u || m2 != 0u) && (m1 == 0u || m2 == 0u)) {
                        if (m1 == 0u) typingWord[i] = typingWord[i] or (TONEW_MASK or AUTO_TONE_MASK)
                        if (m2 == 0u) typingWord[i + 1] = typingWord[i + 1] or (TONEW_MASK or AUTO_TONE_MASK)
                        repaired = true
                    }
                }
            }
        }

        return repaired
    }

    fun interceptBeforeKeyEvent(
        keyCode: UShort,
        preContext: OKWordContext
    ): HookSnapshot? {
        if (!isEnabled || !shorthandExpansionEnabled) return null
        if (keyCode != KEY_SPACE) return null
        if (preContext.spaceCount != 0 || preContext.charCount <= 0 || preContext.composedWord.isEmpty()) {
            return null
        }

        val expanded = expandShorthand(preContext.composedWord) ?: return null
        val fullText = "$expanded "
        val chars = fullText.map { it.code.toUShort() }
        val bs = preContext.charCount.coerceAtMost(32)

        if (candidateSuggestionsEnabled) {
            val nextCands = computeNextWordCandidates(expanded)
            updateCandidates(nextCands)
        }

        return HookSnapshot(
            code = HookCodeState.WILL_PROCESS,
            backspaceCount = bs,
            newCharCount = chars.size,
            extCode = 4,
            shouldSendControlKey = false,
            utf16Chars = chars
        )
    }

    fun didProcessKeyEvent(
        keyCode: UShort,
        snapshot: HookSnapshot,
        preContext: OKWordContext,
        postContext: OKWordContext
    ) {
        val genId = nextGenerationId()

        if (!isEnabled || !candidateSuggestionsEnabled) {
            clearCandidates()
            return
        }

        if (snapshot.code == HookCodeState.RESTORE || snapshot.code == HookCodeState.RESTORE_AND_START_NEW_SESSION) {
            clearCandidates()
            return
        }

        if (keyCode == KEY_SPACE) {
            if (preContext.composedWord.isNotEmpty()) {
                val word = preContext.composedWord
                submitCandidateTaskForGeneration(genId) {
                    computeNextWordCandidates(word)
                }
            } else {
                clearCandidates()
            }
            return
        }

        fun updateLiveCandidates() {
            submitCandidateTaskForGeneration(genId) {
                if (postContext.spaceCount == 0 && postContext.charCount > 0 &&
                    (postContext.rawKeystrokes.length >= 2 || postContext.composedWord.length >= 2)
                ) {
                    computeCurrentWordCandidates(
                        rawStem = postContext.rawKeystrokes,
                        currentSyllable = postContext.composedWord,
                        isWrongSpelling = postContext.isWrongSpelling,
                        languagePriority = VietnameseEngineState.shared.effectiveLanguagePriority()
                    )
                } else {
                    emptyList()
                }
            }
        }

        if (keyCode == KEY_DELETE) {
            updateLiveCandidates()
            return
        }

        if (postContext.isBreakKey || postContext.charCount == 0) {
            clearCandidates()
            return
        }

        updateLiveCandidates()
    }
}
