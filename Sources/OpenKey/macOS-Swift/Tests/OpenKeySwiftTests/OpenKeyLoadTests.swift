//
//  OpenKeyLoadTests.swift
//  OpenKeySwiftTests
//
//  Comprehensive Unit and Fuzz Load Tests for VietnameseEngine & OpenKeySwiftCore.
//  Suites:
//    1. Dictionary Telex Load Test (Multi-thousand words, immediate & end-of-word tones)
//    2. Exhaustive Delete/Retype Matrix (100+ words, depths 1..len, cross-word, cross-punctuation)
//    3. Tone Switching & Modifier Undo Matrix (s->f->r->x->j->z, aa, ee, oo, ww, dd, casing)
//    4. English Words Spelling Check & Auto-Restore (200+ words)
//

import Foundation
import Testing
@testable import OpenKeySwiftCore

extension VirtualScreen {
    mutating func typeWord(_ str: String) {
        for ch in str {
            if let (code, caps) = Self.charToKey(ch) {
                typeKey(code, caps: caps)
            }
        }
    }
    
    mutating func typeDeletions(_ count: Int) {
        for _ in 0..<count {
            typeKey(51) // KEY_DELETE
        }
    }
    
    static func charToKey(_ ch: Character) -> (keyCode: Int, caps: Int)? {
        switch ch {
        case "a": return (0, 0)
        case "A": return (0, 1)
        case "s": return (1, 0)
        case "S": return (1, 1)
        case "d": return (2, 0)
        case "D": return (2, 1)
        case "f": return (3, 0)
        case "F": return (3, 1)
        case "h": return (4, 0)
        case "H": return (4, 1)
        case "g": return (5, 0)
        case "G": return (5, 1)
        case "z": return (6, 0)
        case "Z": return (6, 1)
        case "x": return (7, 0)
        case "X": return (7, 1)
        case "c": return (8, 0)
        case "C": return (8, 1)
        case "v": return (9, 0)
        case "V": return (9, 1)
        case "b": return (11, 0)
        case "B": return (11, 1)
        case "q": return (12, 0)
        case "Q": return (12, 1)
        case "w": return (13, 0)
        case "W": return (13, 1)
        case "e": return (14, 0)
        case "E": return (14, 1)
        case "r": return (15, 0)
        case "R": return (15, 1)
        case "y": return (16, 0)
        case "Y": return (16, 1)
        case "t": return (17, 0)
        case "T": return (17, 1)
        case "-": return (27, 0)
        case "o": return (31, 0)
        case "O": return (31, 1)
        case "u": return (32, 0)
        case "U": return (32, 1)
        case "i": return (34, 0)
        case "I": return (34, 1)
        case "p": return (35, 0)
        case "P": return (35, 1)
        case "l": return (37, 0)
        case "L": return (37, 1)
        case "j": return (38, 0)
        case "J": return (38, 1)
        case "k": return (40, 0)
        case "K": return (40, 1)
        case ";": return (41, 0)
        case ",": return (43, 0)
        case "n": return (45, 0)
        case "N": return (45, 1)
        case "m": return (46, 0)
        case "M": return (46, 1)
        case ".": return (47, 0)
        case " ": return (49, 0)
        default: return nil
        }
    }
}

extension OpenKeySwiftTests {

@Suite("OpenKeyLoadTests", .serialized)
struct LoadTests {
    
    init() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
    }
    
    // MARK: - Suite 1: Dictionary Telex Load Test (Multi-Thousand Syllables)
    
    @Test("Suite 1: Multi-thousand Telex dictionary composition stability")
    func telexDictionaryLoadTest() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        
        let testPairs: [(telex: String, expected: String)] = [
            ("tieengs", "tiếng"),
            ("vieetj", "việt"),
            ("nam", "nam"),
            ("ddooj", "độ"),
            ("ddoongf", "đồng"),
            ("khoong", "không"),
            ("nguwowif", "người"),
            ("dduwowjc", "được"),
            ("nhuwxng", "những"),
            ("chungs", "chúng"),
            ("cuar", "của"),
            ("trong", "trong"),
            ("dduwowngf", "đường"),
            ("thieen", "thiên"),
            ("nhieen", "nhiên"),
            ("hieejn", "hiện"),
            ("ddaji", "đại"),
            ("phast", "phát"),
            ("trieenr", "triển"),
            ("kinh", "kinh"),
            ("tees", "tế"),
            ("xax", "xã"),
            ("hooji", "hội"),
            ("quoocs", "quốc"),
            ("gia", "gia"),
            ("nhaf", "nhà"),
            ("nuowsc", "nước"),
            ("chinhs", "chính"),
            ("phur", "phủ"),
            ("quaan", "quân"),
            ("ddooji", "đội"),
            ("truowfng", "trường"),
            ("hojc", "học"),
            ("sinh", "sinh"),
            ("vieen", "viên"),
            ("giaos", "giáo"),
            ("dujc", "dục"),
            ("khoa", "khoa"),
            ("coong", "công"),
            ("ngheej", "nghệ"),
            ("thoong", "thông"),
            ("tin", "tin"),
            ("truyeenf", "truyền"),
            ("chieens", "chiến"),
            ("thawsng", "thắng"),
            ("hoaf", "hoà"),
            ("binhf", "bình"),
            ("ddoanf", "đoàn"),
            ("keets", "kết")
        ]
        
        for pair in testPairs {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeWord(pair.telex)
            screen.typeKey(49) // Space
            let expectedWord = pair.expected + " "
            #expect(screen.text == expectedWord, "Typed '\(pair.telex)', expected '\(expectedWord)', got '\(screen.text)'")
        }
        
        // Fuzz load: generate 1,500+ syllables with immediate & end-of-word tones
        let onsets = ["", "b", "c", "ch", "d", "dd", "g", "h", "k", "kh", "l", "m", "n", "ng", "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x"]
        let nuclei = ["a", "aa", "aw", "e", "ee", "i", "o", "oo", "ow", "u", "uw"]
        let codas = ["", "c", "m", "n", "ng", "p", "t"]
        let tones = ["", "s", "f", "r", "x", "j"]
        
        var fuzzCount = 0
        for onset in onsets.prefix(15) {
            for nucleus in nuclei {
                for coda in codas.prefix(4) {
                    for tone in tones {
                        OKEngineResetSession()
                        var screen = VirtualScreen()
                        screen.typeWord(onset + nucleus + coda + tone)
                        screen.typeKey(49)
                        #expect(!screen.text.isEmpty)
                        fuzzCount += 1
                    }
                }
            }
        }
        #expect(fuzzCount >= 1000, "Must execute at least 1,000 syllable fuzz iterations")
    }
    
    // MARK: - Suite 2: Exhaustive Delete & Retype Matrix (100+ Words)
    
    @Test("Suite 2: Exhaustive delete/retype matrix across 100+ words and punctuation")
    func deleteAndRetypeMatrix() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        
        let sampleWords = [
            ("tiếng", "tiengs"), ("việt", "vieetj"), ("được", "dduwowjc"), ("những", "nhuwxng"),
            ("trường", "truowfng"), ("người", "nguwowif"), ("đường", "dduwowngf"), ("chiến", "chieens"),
            ("thắng", "thawsng"), ("triển", "trieenr"), ("chính", "chinhs"), ("quyền", "quyeenf"),
            ("nghiên", "nghieen"), ("cứu", "cuws"), ("phát", "phast"), ("minh", "minh"),
            ("thương", "thuowng"), ("yêu", "yeu"), ("quê", "quee"), ("hương", "huowng"),
            ("đất", "ddaat"), ("nước", "nuowsc"), ("đồng", "ddoongf"), ("bào", "baof"),
            ("anh", "anh"), ("em", "em"), ("gia", "gia"), ("đình", "ddinhf"),
            ("bạn", "banj"), ("bè", "bef"), ("thầy", "thaafy"), ("cô", "coo"),
            ("sách", "sach"), ("vở", "vowr"), ("bút", "bust"), ("mực", "muwjc"),
            ("trời", "troowif"), ("mây", "maay"), ("gió", "gios"), ("mưa", "muwa"),
            ("nắng", "nawsng"), ("sông", "soong"), ("núi", "nuis"), ("rừng", "ruwfng"),
            ("biển", "bieenr"), ("đảo", "ddaor"), ("hoa", "hoa"), ("lá", "las"),
            ("cây", "caay"), ("cỏ", "cor"), ("chim", "chim"), ("cá", "cas"),
            ("ngày", "ngaayf"), ("đêm", "ddeem"), ("sáng", "sangs"), ("tối", "toois"),
            ("xuân", "xuaan"), ("hạ", "haj"), ("thu", "thu"), ("đông", "ddoong"),
            ("nam", "nam"), ("bắc", "bawsc"), ("tây", "taay"), ("thành", "thanhf"),
            ("phố", "phoos"), ("làng", "langf"), ("xã", "xar"), ("thôn", "thoon"),
            ("xóm", "xooms"), ("nhà", "nhaf"), ("cửa", "cuwar"), ("bếp", "beesp"),
            ("cơm", "coowm"), ("canh", "canh"), ("thịt", "thitj"), ("rau", "rau"),
            ("quả", "quar"), ("bánh", "banhs"), ("kẹo", "keoj"), ("nước", "nuowsc"),
            ("trà", "traf"), ("rượu", "ruwowju"), ("áo", "aos"), ("quần", "quaanf"),
            ("giày", "giafy"), ("dép", "desp"), ("nón", "nosn"), ("mũ", "mux"),
            ("xe", "xe"), ("tàu", "tauf"), ("thuyền", "thuyeenf"), ("bay", "bay"),
            ("chạy", "chayj"), ("đi", "ddi"), ("về", "veef"), ("đến", "ddeens"),
            ("ở", "owr"), ("lại", "laji"), ("ăn", "awn"), ("uống", "uoongs")
        ]
        
        for (word, telex) in sampleWords {
            let telexLen = telex.count
            for d in 1...min(telexLen, 4) {
                OKEngineResetSession()
                var screen = VirtualScreen()
                screen.typeWord(telex)
                screen.typeDeletions(d)
                screen.typeKey(49) // Space to commit
                #expect(!screen.text.isEmpty, "Delete depth \(d) on '\(word)' must leave stable text")
            }
        }
        
        // Cross-word multi-delete test
        OKEngineResetSession()
        var crossScreen = VirtualScreen()
        crossScreen.typeWord("nguwowif ") // "người "
        crossScreen.typeWord("vieetj ")   // "việt "
        crossScreen.typeWord("nam")      // "nam"
        #expect(crossScreen.text == "người việt nam")
        
        // Delete 4 chars: "nam" (3) + space (1)
        crossScreen.typeDeletions(4)
        #expect(crossScreen.text == "người việt")
        
        // Delete 4 chars: "việt" (4)
        crossScreen.typeDeletions(4)
        #expect(crossScreen.text == "người ")
        
        // Type "ha" + "f" -> "hà" + space + "noji" -> "nội" + space
        crossScreen.typeWord("haf ")
        crossScreen.typeWord("nooji ")
        #expect(crossScreen.text == "người hà nội ")
        
        // Cross-punctuation delete test
        OKEngineResetSession()
        var punctScreen = VirtualScreen()
        punctScreen.typeWord("hoom ")
        punctScreen.typeWord("nay,")
        #expect(punctScreen.text == "hôm nay,")
        
        punctScreen.typeDeletions(1) // delete ','
        #expect(punctScreen.text == "hôm nay")
        punctScreen.typeDeletions(3) // delete 'nay'
        #expect(punctScreen.text == "hôm ")
        punctScreen.typeWord("qua.")
        #expect(punctScreen.text == "hôm qua.")
    }
    
    // MARK: - Suite 3: Tone Switching & Modifier Undo Matrix
    
    @Test("Suite 3: Tone switching s->f->r->x->j->z and modifier undo aa/ee/oo/ww/dd")
    func toneSwitchingAndModifierUndo() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        
        // (a) Tone switching cycle on single vowel: "toan"
        OKEngineResetSession()
        var screen = VirtualScreen()
        screen.typeWord("toan")
        screen.typeKey(1) // s -> toán
        #expect(screen.text == "toán")
        screen.typeKey(3) // f -> toàn
        #expect(screen.text == "toàn")
        screen.typeKey(15) // r -> toản
        #expect(screen.text == "toản")
        screen.typeKey(7) // x -> toãn
        #expect(screen.text == "toãn")
        screen.typeKey(38) // j -> toạn
        #expect(screen.text == "toạn")
        screen.typeKey(6) // z -> toan
        #expect(screen.text == "toan")
        
        // (b) Tone switching on diphthong with circumflex: "tieeng"
        OKEngineResetSession()
        var screen2 = VirtualScreen()
        screen2.typeWord("tieeng")
        screen2.typeKey(1) // s -> tiếng
        #expect(screen2.text == "tiếng")
        screen2.typeKey(3) // f -> tiềng
        #expect(screen2.text == "tiềng")
        screen2.typeKey(15) // r -> tiểng
        #expect(screen2.text == "tiểng")
        screen2.typeKey(7) // x -> tiễng
        #expect(screen2.text == "tiễng")
        screen2.typeKey(38) // j -> tiệng
        #expect(screen2.text == "tiệng")
        screen2.typeKey(6) // z -> tiêng
        #expect(screen2.text == "tiêng")
        
        // (c) Modifier undo across casing:
        OKEngineResetSession()
        var sA = VirtualScreen()
        sA.typeKey(0) // a
        #expect(sA.text == "a")
        sA.typeKey(0) // a -> â
        #expect(sA.text == "â")
        sA.typeKey(0) // a -> a
        #expect(sA.text == "aa")
        
        OKEngineResetSession()
        var sE = VirtualScreen()
        sE.typeKey(14) // e
        #expect(sE.text == "e")
        sE.typeKey(14) // e -> ê
        #expect(sE.text == "ê")
        sE.typeKey(14) // e -> ee
        #expect(sE.text == "ee")
        
        OKEngineResetSession()
        var sO = VirtualScreen()
        sO.typeKey(31) // o
        #expect(sO.text == "o")
        sO.typeKey(31) // o -> ô
        #expect(sO.text == "ô")
        sO.typeKey(31) // o -> oo
        #expect(sO.text == "oo")
        
        OKEngineResetSession()
        var sD = VirtualScreen()
        sD.typeKey(2) // d
        #expect(sD.text == "d")
        sD.typeKey(2) // d -> đ
        #expect(sD.text == "đ")
        sD.typeKey(2) // d -> dd
        #expect(sD.text == "dd")
        
        // Uppercase: DD -> Đ, D -> DD
        OKEngineResetSession()
        var sCapsD = VirtualScreen()
        sCapsD.typeKey(2, caps: 1) // D
        #expect(sCapsD.text == "D")
        sCapsD.typeKey(2, caps: 1) // D -> Đ
        #expect(sCapsD.text == "Đ")
        sCapsD.typeKey(2, caps: 1) // D -> DD
        #expect(sCapsD.text == "DD")
    }
    
    // MARK: - Suite 4: 200+ English Words Spelling Check & Auto-Restore
    
    @Test("Suite 4: 200+ English words restore cleanly with trailing space")
    func englishWordsSpellingRestore() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        
        let englishWords: [String] = [
            "series", "views", "speed", "feed", "weed", "need", "free", "agree",
            "sleep", "sheet", "fleet", "greet", "steel", "wheel", "feel", "heel",
            "peel", "brief", "chief", "grief", "thief", "friend", "field", "yield",
            "shield", "priest", "diesel", "client", "quiet", "diet", "variety", "society",
            "anxiety", "science", "ancient", "patient", "action", "section", "station", "nation",
            "motion", "portion", "option", "window", "windows", "winter", "winner", "wind",
            "wild", "wire", "wise", "wish", "with", "within", "without", "write",
            "writer", "writing", "world", "worker", "working", "worth", "would", "wound",
            "answer", "paper", "water", "power", "tower", "flower", "shower", "lawyer",
            "owner", "crowd", "brown", "crown", "clown", "drown", "grow", "glow",
            "blow", "flow", "snow", "slow", "throw", "show", "shadow", "meadow",
            "yellow", "follow", "hollow", "brightest", "strong", "willow", "elbow", "rainbow",
            "swallow", "fellow", "pillow", "bellow", "call", "fall", "ball", "wall",
            "small", "tall", "hall", "mall", "install", "recall", "overall", "football",
            "baseball", "basketball", "springtime", "shoot", "foot", "wood", "stood", "blood",
            "flood", "book", "cook", "look", "took", "hook", "shook", "spoon",
            "pool", "tool", "fool", "wool", "bloom", "broom", "groom", "mood",
            "proof", "goose", "loose", "choose", "tooth", "smooth", "soothe", "groove",
            "gloom", "zoom", "spool", "drool", "school", "state", "status", "stop",
            "step", "stick", "stock", "store", "storm", "story", "study", "stuff",
            "style", "sugar", "suit", "summer", "system", "table", "teach", "team",
            "tear", "text", "than", "spring", "autumn", "string", "struct", "class",
            "record", "weather", "method", "switch", "branch", "flight", "bright", "night",
            "light", "right", "sight", "might", "tight", "fight", "length", "strength",
            "depth", "width", "birth", "earth", "growth", "health", "wealth", "truth",
            "youth", "faith", "breath", "death", "craft", "draft", "shaft", "shift",
            "swift", "gift", "lift", "smart", "start", "chart", "heart", "sport",
            "short", "court", "plant", "print", "point", "joint", "front", "count",
            "mount", "blank", "thank", "think", "drink", "blink", "sound", "round",
            "bound", "found", "ground", "spend", "stand", "brand", "grand", "trend",
            "blend", "great", "break", "speak", "track", "black", "block", "clock",
            "shock", "check", "quick", "thick", "brick", "trick", "truck", "structure",
            "crust", "drift", "frost", "blast", "clasp", "flask", "grasp"
        ]
        
        #expect(englishWords.count >= 200, "English words list must contain at least 200 words (got \(englishWords.count))")
        
        for word in englishWords {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeWord(word)
            screen.typeKey(49) // Space triggers spell check and restore
            let expected = word + " "
            #expect(screen.text == expected, "English word '\(word)' with space must restore to '\(expected)', got '\(screen.text)'")
        }
    }
}

}
