import Foundation
import SwiftUI
import Combine

/// 语言管理与国际化支持 (中英双语)
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    @Published public private(set) var currentLanguage: String = "system"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        SiriusPreferences.shared.$appLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lang in
                self?.currentLanguage = lang
            }
            .store(in: &cancellables)
    }

    /// 是否当前解析为英文
    public var isEnglish: Bool {
        let lang = SiriusPreferences.shared.appLanguage
        if lang == "en" { return true }
        if lang == "zh" { return false }
        // 跟随系统
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "zh"
        return !preferred.starts(with: "zh")
    }

    /// 获取本地化文本
    public func text(_ zh: String, _ en: String) -> String {
        return isEnglish ? en : zh
    }
}

/// 全局快捷本地化函数
public func loc(_ zh: String, _ en: String) -> String {
    LocalizationManager.shared.text(zh, en)
}
