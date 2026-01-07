import AppKit
import UniformTypeIdentifiers

// MARK: - Drag Drop Result

/// 拖拽解析结果
struct DragDropResult {
    /// 解析出的文件 URL 数组
    let urls: [URL]
    /// 解析出的图片对象数组（通常来自网页拖拽）
    let images: [NSImage]

    /// 是否为空
    var isEmpty: Bool {
        urls.isEmpty && images.isEmpty
    }

    /// 内容总数
    var totalCount: Int {
        urls.count + images.count
    }
}

// MARK: - Drag Drop Parser

/// 统一的拖拽内容解析器
///
/// 负责解析从外部拖入应用的 NSItemProvider，支持：
/// - NSImage（网页拖拽图片）
/// - URL（文件路径）
/// - String（本地路径和 HTTP URL）
/// - Data（通过 loadItem 兜底处理）
enum DragDropParser {

    /// 解析拖拽内容
    ///
    /// 此方法会按照优先级尝试解析每个 provider：
    /// 1. NSImage - 优先处理图片（网页拖拽场景）
    /// 2. URL - 处理文件 URL
    /// 3. String - 处理路径字符串和 HTTP URL
    /// 4. loadItem - 兜底方案，尝试从原始数据中提取 URL
    ///
    /// - Parameter providers: NSItemProvider 数组，通常来自 `.onDrop` 修饰符
    /// - Parameter completion: 完成回调，在主线程执行，返回解析结果
    ///
    /// # 使用示例
    /// ```swift
    /// .onDrop(of: [.item, .fileURL, .text, .url]) { providers in
    ///     DragDropParser.parse(providers: providers) { result in
    ///         if !result.isEmpty {
    ///             store.handleDroppedContent(urls: result.urls, images: result.images)
    ///         }
    ///     }
    ///     return true
    /// }
    /// ```
    static func parse(
        providers: [NSItemProvider],
        completion: @escaping (DragDropResult) -> Void
    ) {
        print("[DEBUG DragDropParser] 开始解析，providers 数量: \(providers.count)")

        guard !providers.isEmpty else {
            print("[DEBUG DragDropParser] providers 为空，返回空结果")
            completion(DragDropResult(urls: [], images: []))
            return
        }

        let dispatchGroup = DispatchGroup()
        var urls: [URL] = []
        var images: [NSImage] = []
        let urlsLock = NSLock()  // 保证线程安全
        let imagesLock = NSLock()

        for (index, provider) in providers.enumerated() {
            dispatchGroup.enter()

            let types = provider.registeredTypeIdentifiers
            print("[DEBUG DragDropParser] provider[\(index)] 注册的类型: \(types)")

            // 1. 优先尝试 NSImage（网页拖拽图片非常有效）
            if provider.canLoadObject(ofClass: NSImage.self) {
                print("[DEBUG DragDropParser] provider[\(index)] 尝试解析为 NSImage")
                _ = provider.loadObject(ofClass: NSImage.self) { [weak imagesLock] image, error in
                    defer {
                        dispatchGroup.leave()
                    }

                    if let error = error {
                        print("[DEBUG DragDropParser] provider[\(index)] NSImage 加载失败: \(error.localizedDescription)")
                        return
                    }

                    if let image = image as? NSImage {
                        print("[DEBUG DragDropParser] provider[\(index)] 成功解析为 NSImage，尺寸: \(image.size)")
                        imagesLock?.lock()
                        images.append(image)
                        imagesLock?.unlock()
                    } else {
                        print("[DEBUG DragDropParser] provider[\(index)] NSImage 类型转换失败")
                    }
                }
            }
            // 2. 其次尝试 URL
            else if provider.canLoadObject(ofClass: URL.self) {
                print("[DEBUG DragDropParser] provider[\(index)] 尝试解析为 URL")
                _ = provider.loadObject(ofClass: URL.self) { [weak urlsLock] url, error in
                    defer {
                        dispatchGroup.leave()
                    }

                    if let error = error {
                        print("[DEBUG DragDropParser] provider[\(index)] URL 加载失败: \(error.localizedDescription)")
                        return
                    }

                    if let url = url {
                        print("[DEBUG DragDropParser] provider[\(index)] 成功解析为 URL: \(url.absoluteString)")
                        urlsLock?.lock()
                        urls.append(url)
                        urlsLock?.unlock()
                    } else {
                        print("[DEBUG DragDropParser] provider[\(index)] URL 为 nil")
                    }
                }
            }
            // 3. 然后尝试 String
            else if provider.canLoadObject(ofClass: String.self) {
                print("[DEBUG DragDropParser] provider[\(index)] 尝试解析为 String")
                _ = provider.loadObject(ofClass: String.self) { [weak urlsLock] str, error in
                    defer {
                        dispatchGroup.leave()
                    }

                    if let error = error {
                        print("[DEBUG DragDropParser] provider[\(index)] String 加载失败: \(error.localizedDescription)")
                        return
                    }

                    guard let str = str else {
                        print("[DEBUG DragDropParser] provider[\(index)] String 为 nil")
                        return
                    }

                    print("[DEBUG DragDropParser] provider[\(index)] 成功解析为 String: \(str)")

                    // 处理本地路径
                    if str.starts(with: "/") {
                        let url = URL(fileURLWithPath: str)
                        print("[DEBUG DragDropParser] provider[\(index)] String 转本地路径 URL: \(url.path)")
                        urlsLock?.lock()
                        urls.append(url)
                        urlsLock?.unlock()
                    }
                    // 处理 HTTP/HTTPS URL
                    else if str.starts(with: "http") {
                        if let url = URL(string: str) {
                            print("[DEBUG DragDropParser] provider[\(index)] String 转 HTTP URL: \(url.absoluteString)")
                            urlsLock?.lock()
                            urls.append(url)
                            urlsLock?.unlock()
                        } else {
                            print("[DEBUG DragDropParser] provider[\(index)] String 转 HTTP URL 失败")
                        }
                    } else {
                        print("[DEBUG DragDropParser] provider[\(index)] String 格式不支持（非路径也非 HTTP）")
                    }
                }
            }
            // 4. 兜底方案：尝试通过 loadItem 加载原始数据
            else if let firstType = types.first {
                print("[DEBUG DragDropParser] provider[\(index)] 尝试 loadItem 兜底，类型: \(firstType)")
                provider.loadItem(forTypeIdentifier: firstType, options: nil) { [weak urlsLock] item, error in
                    defer {
                        dispatchGroup.leave()
                    }

                    if let error = error {
                        print("[DEBUG DragDropParser] provider[\(index)] loadItem 失败: \(error.localizedDescription)")
                        return
                    }

                    // 尝试转换为 URL
                    if let url = item as? URL {
                        print("[DEBUG DragDropParser] provider[\(index)] loadItem 成功获取 URL: \(url.path)")
                        urlsLock?.lock()
                        urls.append(url)
                        urlsLock?.unlock()
                    }
                    // 尝试从 Data 创建 URL
                    else if let data = item as? Data,
                            let url = URL(dataRepresentation: data, relativeTo: nil) {
                        print("[DEBUG DragDropParser] provider[\(index)] loadItem 从 Data 获取到 URL: \(url.path)")
                        urlsLock?.lock()
                        urls.append(url)
                        urlsLock?.unlock()
                    }
                    // 记录无法处理的类型
                    else if let item = item {
                        print("[DEBUG DragDropParser] provider[\(index)] loadItem 获取到无法处理的类型: \(type(of: item))")
                    } else {
                        print("[DEBUG DragDropParser] provider[\(index)] loadItem 返回 nil")
                    }
                }
            } else {
                // 没有可用的类型，直接 leave
                print("[DEBUG DragDropParser] provider[\(index)] 没有可用的类型标识符")
                dispatchGroup.leave()
            }
        }

        // 所有解析完成后，在主线程回调
        dispatchGroup.notify(queue: .main) {
            print("[DEBUG DragDropParser] 解析完成 - URLs: \(urls.count), Images: \(images.count)")
            completion(DragDropResult(urls: urls, images: images))
        }
    }
}
