import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeDocumentsFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// [A-06-7] 앱 데이터(Documents — library/·index/·drafts/·reading_positions/)를 iCloud 백업에서 뺀다.
  ///
  /// 왜: 아이 사진·보호자 녹음은 기기 밖으로 나가지 않아야 한다(오너 결정 2026-10-06).
  /// Dart(path_provider)에는 백업 제외 API 가 없어 여기서 한다. 디렉터리에 표시하면 안의 파일도 빠진다.
  /// 복원 등으로 속성이 사라질 수 있어 매 실행마다 다시 건다.
  private func excludeDocumentsFromBackup() {
    guard var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
    } catch {
      // 실패해도 앱 실행은 막지 않는다 — 다음 실행에서 다시 시도한다. 경로(사용자 데이터 위치)는 남기지 않는다.
      NSLog("E-MCR-500 iCloud 백업 제외 설정 실패")
    }
  }
}
