import Foundation

/// 应用元信息
/// 版本号单一数据源：打包时由 `scripts/build_app.sh` 从 git tag 写入 Info.plist，
/// 应用内一律读取 `CFBundleShortVersionString`，避免源码里散落硬编码版本号导致发布漂移。
public enum AppInfo {
    /// 语义化版本号，例如 "1.2.0"（非打包环境运行源码时返回 "dev"）
    public static let version: String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }()

    /// 带产品名前缀的版本串，例如 "Sirius v1.2.0"
    public static var displayVersion: String { "Sirius v\(version)" }
}
