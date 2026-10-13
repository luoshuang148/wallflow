import Foundation

public enum WallpaperSearch {
    public static func filter(_ projects: [WallpaperProject], query: String, customNames: [String:String] = [:]) -> [WallpaperProject] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return projects }
        return projects.filter { project in
            let folder = URL(fileURLWithPath: project.sourceFolderPath ?? project.folderPath).lastPathComponent
            let text = project.title + " " + (customNames[project.id] ?? "") + " " + folder
            return terms.allSatisfy { term in
                text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current) != nil
            }
        }
    }
}
