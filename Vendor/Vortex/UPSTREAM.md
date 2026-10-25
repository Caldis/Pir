# Vortex 来源

读者: Pir 维护者

源码来自 twostraws/Vortex 1.0.4, 提交 9d9d9016ceace579455f01f8e0bd59facae7d252, 采用 MIT 许可证

Sources 保持上游内容. 本地 Package.swift 仅声明 macOS 产品与显式 Assets.xcassets 资源处理, 支持标准 SwiftPM 和 Xcode 构建系统

## 设计决策

上游清单缺少资源声明, 标准 SwiftPM 构建缺少 Bundle.module. Pir 固定源码与资源, 使用显式资源声明构建同一版本
