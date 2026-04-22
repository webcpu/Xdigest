import XdigestCore

func sectionKey(for section: DigestSection, date: String) -> String? {
    guard let firstPostId = section.posts.first?.tweet.id, !firstPostId.isEmpty else {
        return nil
    }
    return "\(date)|\(section.timestamp)|\(firstPostId)"
}

func latestSectionKey(in digest: Digest) -> String? {
    guard let latestSection = digest.sections.first else { return nil }
    return sectionKey(for: latestSection, date: digest.date)
}
