// NavStackProbe.swift — 拿到 NavigationStack 背后的 UINavigationController（自愈与诊断共用）。
// 放在 NavigationStack 根内容的 .background 里。根视图每次出现都会回调，并打印
// UINavigationController / 侧滑手势的 delegate —— 用来发现"delegate 被别人换掉"
// 以及冷启动 1–2 秒内的状态变化。

import SwiftUI
import UIKit

struct NavStackProbe: UIViewControllerRepresentable {
    let onResolve: (UINavigationController) -> Void

    func makeUIViewController(context: Context) -> ProbeVC { ProbeVC(onResolve: onResolve) }
    func updateUIViewController(_ vc: ProbeVC, context: Context) {}

    final class ProbeVC: UIViewController {
        private let onResolve: (UINavigationController) -> Void

        init(onResolve: @escaping (UINavigationController) -> Void) {
            self.onResolve = onResolve
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let nav = navigationController else { return }
            onResolve(nav)
            NavLog.dump(nav)
        }
    }
}
