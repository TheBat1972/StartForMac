import Foundation

/// «Избранное» из боковой панели Finder.
/// 1) файл ~/Library/Application Support/com.apple.sharedfilelist (архив NSKeyedArchiver, у каждого пункта закладка «book…»);
/// 2) если не вышло — старый интерфейс LSSharedFileList (объявлен устаревшим, но Finder им ещё отвечает).
enum FinderFavorites {
    struct Result {
        var folders: [URL] = []
        /// Почему список пуст (показывается в меню серой строкой)
        var note: String? = nil
    }

    static func load() -> Result {
        var r = Result()
        var denied = false
        var found = false
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
        for name in ["com.apple.LSSharedFileList.FavoriteItems.sfl3", "com.apple.LSSharedFileList.FavoriteItems.sfl2"] {
            let url = dir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            found = true
            guard let data = try? Data(contentsOf: url) else { denied = true; continue }
            let list = fromArchive(data)
            if !list.isEmpty { r.folders = list; return r }
        }
        let ls = viaLaunchServices()
        if !ls.isEmpty { r.folders = ls; return r }
        if denied { r.note = T("Избранное Finder не прочитано: нужен «Полный доступ к диску»") }
        else if !found { r.note = T("Избранное Finder не найдено") }
        else { r.note = T("В избранном Finder нет папок") }
        return r
    }

    private static func resolve(_ d: Data) -> URL? {
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: d, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return u
    }

    private static func fromArchive(_ data: Data) -> [URL] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let objs = plist["$objects"] as? [Any] else { return [] }
        var out: [URL] = []
        var seen = Set<String>()
        for o in objs {
            guard let d = o as? Data, d.count > 8, d.prefix(4) == Data("book".utf8), let u = resolve(d) else { continue }
            if seen.insert(u.path).inserted { out.append(u) }
        }
        return out
    }

    /// Старый интерфейс LSSharedFileList: подключается по имени во время работы, а не при сборке,
    /// поэтому компилятор не ругается на «устаревшее», а если системы функций нет — просто вернётся пустой список.
    private static func viaLaunchServices() -> [URL] {
        let def = UnsafeMutableRawPointer(bitPattern: -2)          // RTLD_DEFAULT
        guard let fc = dlsym(def, "LSSharedFileListCreate"), let fs = dlsym(def, "LSSharedFileListCopySnapshot"),
              let fr = dlsym(def, "LSSharedFileListItemCopyResolvedURL"), let kp = dlsym(def, "kLSSharedFileListFavoriteItems") else { return [] }
        typealias Create = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        typealias Snapshot = @convention(c) (UnsafeRawPointer?, UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer?
        typealias Resolve = @convention(c) (UnsafeRawPointer?, UInt32, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let create = unsafeBitCast(fc, to: Create.self)
        let snapshot = unsafeBitCast(fs, to: Snapshot.self)
        let resolve = unsafeBitCast(fr, to: Resolve.self)
        let key = kp.assumingMemoryBound(to: UnsafeRawPointer?.self).pointee
        guard let list = create(nil, key, nil) else { return [] }
        defer { Unmanaged<AnyObject>.fromOpaque(list).release() }
        var seed: UInt32 = 0
        guard let arr = snapshot(UnsafeRawPointer(list), &seed) else { return [] }
        let items = Unmanaged<NSArray>.fromOpaque(arr).takeRetainedValue() as [AnyObject]
        var out: [URL] = []
        var seen = Set<String>()
        for it in items {
            // флаги: 1 — без вопросов пользователю, 2 — не подключать тома
            guard let up = resolve(UnsafeRawPointer(Unmanaged.passUnretained(it).toOpaque()), 3, nil) else { continue }
            let u = Unmanaged<NSURL>.fromOpaque(up).takeRetainedValue() as URL
            var isDir: ObjCBool = false
            guard u.isFileURL, FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if seen.insert(u.path).inserted { out.append(u) }
        }
        return out
    }
}
