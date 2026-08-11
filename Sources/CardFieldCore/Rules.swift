import Foundation

public enum PhoneKind: String, Codable, CaseIterable, Sendable {
  case mobile
  case work
  case fax
}

/// A portable, additive vocabulary pack. Packs cannot execute code or make network requests.
public struct RulePack: Codable, Equatable, Sendable {
  public var schemaVersion: String
  public var identifier: String
  public var version: String
  public var locale: String?
  public var industry: String?
  public var priority: Int
  public var organizationSuffixes: [String]
  public var organizationTerms: [String]
  public var jobTitles: [String]
  public var departmentTerms: [String]
  public var phoneLabels: [String: PhoneKind]
  public var addressTerms: [String]
  public var sloganTerms: [String]

  public init(
    schemaVersion: String = "1.0",
    identifier: String,
    version: String,
    locale: String? = nil,
    industry: String? = nil,
    priority: Int = 0,
    organizationSuffixes: [String] = [],
    organizationTerms: [String] = [],
    jobTitles: [String] = [],
    departmentTerms: [String] = [],
    phoneLabels: [String: PhoneKind] = [:],
    addressTerms: [String] = [],
    sloganTerms: [String] = []
  ) {
    self.schemaVersion = schemaVersion
    self.identifier = identifier
    self.version = version
    self.locale = locale
    self.industry = industry
    self.priority = priority
    self.organizationSuffixes = organizationSuffixes
    self.organizationTerms = organizationTerms
    self.jobTitles = jobTitles
    self.departmentTerms = departmentTerms
    self.phoneLabels = phoneLabels
    self.addressTerms = addressTerms
    self.sloganTerms = sloganTerms
  }
}

enum BaseRules {
  static let version = "base-1.1.0"

  static let pack = RulePack(
    identifier: "org.businesscardfieldkit.base",
    version: version,
    organizationSuffixes: [
      "inc", "inc.", "llc", "ltd", "ltd.", "corp", "corporation", "company", "co.",
      "group", "partners", "holdings", "ventures", "venture", "capital", "studio", "labs", "lab",
      "works", "systems", "technology", "technologies", "solutions",
      "주식회사", "(주)", "㈜", "유한회사", "(재)", "재단", "재단법인", "협회", "연구원",
      "연구소",
    ],
    organizationTerms: [
      "university", "college", "school", "institute", "foundation", "association", "agency",
      "ministry", "department of", "government", "council", "authority", "commission", "center",
      "대학교", "대학", "정부", "청", "부", "위원회", "공단", "공사", "센터",
    ],
    jobTitles: [
      "chief executive officer", "chief technology officer", "chief operating officer",
      "chief legal officer", "ceo", "cto", "coo", "clo",
      "founder", "co-founder", "president", "vice president", "chairman", "group chairman",
      "director", "manager", "lead", "head",
      "engineer", "designer", "developer", "architect", "researcher", "scientist", "professor",
      "attorney",
      "consultant", "specialist", "coordinator", "officer", "partner", "principal", "analyst",
      "대표", "대표이사", "이사", "상무", "전무", "부장", "차장", "과장", "대리", "주임", "사원",
      "교수", "연구원", "변호사", "팀장", "실장", "센터장", "본부장", "주무관", "전문위원", "매니저",
      "엔지니어", "디자이너",
    ],
    departmentTerms: [
      "engineering", "design", "product", "marketing", "sales", "finance", "operations", "research",
      "investment", "analytics", "customer services", "online marketing", "export support",
      "global business", "industry policy",
      "human resources", "business development", "legal", "communications", "전략", "기획", "개발",
      "디자인", "마케팅", "영업", "재무", "인사", "홍보", "연구", "사업개발", "법무", "정책과",
      "지원센터", "사업본부", "사업팀", "산업정책본부", "팀", "부서",
    ],
    phoneLabels: [
      "m": .mobile, "c": .mobile, "mobile": .mobile, "cell": .mobile, "mob": .mobile,
      "모바일": .mobile,
      "휴대": .mobile, "휴대폰": .mobile, "핸드폰": .mobile,
      "o": .work, "t": .work, "d": .work, "tel": .work, "telephone": .work,
      "office": .work, "phone": .work, "전화": .work, "직통": .work,
      "f": .fax, "fax": .fax, "팩스": .fax,
    ],
    addressTerms: [
      "address", "registered address", "reg address", "street", "st.", "road", "rd.", "avenue",
      "ave", "boulevard", "blvd", "lane", "suite",
      "floor",
      "building", "drive", "tower", "park", "plaza", "district", "city", "state", "province",
      "postal", "zip", "서울", "부산",
      "대구",
      "인천", "광주", "대전", "울산", "세종", "경기", "강원", "충청", "전라", "경상", "제주", "로", "길",
      "구", "동", "번지", "층",
    ],
    sloganTerms: [
      "we build", "building the", "better future", "future of", "your partner", "trusted partner",
      "lifetime value", "creating value", "connecting people", "innovation for", "together we",
      "since ",
      "더 나은", "함께 만드는", "가치를", "미래를", "사람과", "연결하는",
    ]
  )
}

struct EffectiveRules {
  var versions: [String]
  var organizationSuffixes: Set<String>
  var organizationTerms: Set<String>
  var jobTitles: Set<String>
  var departmentTerms: Set<String>
  var phoneLabels: [String: PhoneKind]
  var addressTerms: Set<String>
  var sloganTerms: Set<String>
  var localePackIdentifiers: Set<String>
  var industryPackIdentifiers: Set<String>
  var localeTerms: Set<String>
  var industryTerms: Set<String>

  init(packs: [RulePack]) {
    let ordered =
      [BaseRules.pack]
      + packs.sorted {
        if $0.priority != $1.priority { return $0.priority < $1.priority }
        return $0.identifier < $1.identifier
      }
    versions = ordered.map { "\($0.identifier)@\($0.version)" }
    organizationSuffixes = Set(ordered.flatMap(\.organizationSuffixes).map(\.cardFieldFolded))
    organizationTerms = Set(ordered.flatMap(\.organizationTerms).map(\.cardFieldFolded))
    jobTitles = Set(ordered.flatMap(\.jobTitles).map(\.cardFieldFolded))
    departmentTerms = Set(ordered.flatMap(\.departmentTerms).map(\.cardFieldFolded))
    addressTerms = Set(ordered.flatMap(\.addressTerms).map(\.cardFieldFolded))
    sloganTerms = Set(ordered.flatMap(\.sloganTerms).map(\.cardFieldFolded))
    localePackIdentifiers = Set(ordered.filter { $0.locale != nil }.map(\.identifier))
    industryPackIdentifiers = Set(ordered.filter { $0.industry != nil }.map(\.identifier))
    localeTerms = Set(
      ordered.filter { $0.locale != nil }.flatMap(Self.allTerms).map(\.cardFieldFolded))
    industryTerms = Set(
      ordered.filter { $0.industry != nil }.flatMap(Self.allTerms).map(\.cardFieldFolded))
    phoneLabels = [:]
    for pack in ordered {
      for (label, kind) in pack.phoneLabels {
        phoneLabels[label.cardFieldFolded] = kind
      }
    }
  }

  private static func allTerms(_ pack: RulePack) -> [String] {
    pack.organizationSuffixes + pack.organizationTerms + pack.jobTitles + pack.departmentTerms
      + Array(pack.phoneLabels.keys) + pack.addressTerms + pack.sloganTerms
  }

  func contains(_ terms: Set<String>, in text: String) -> Bool {
    let folded = text.cardFieldFolded
    return terms.contains { term in
      guard folded != term else { return true }
      let hasCJK = term.unicodeScalars.contains { scalar in
        (0x3040...0x30FF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
          || (0x4E00...0x9FFF).contains(scalar.value) || (0xAC00...0xD7A3).contains(scalar.value)
      }
      if hasCJK || term.contains(" ") { return folded.contains(term) }
      let normalizedTerm = term.trimmingCharacters(in: .punctuationCharacters)
      let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
      return words.contains(normalizedTerm)
    }
  }
}
