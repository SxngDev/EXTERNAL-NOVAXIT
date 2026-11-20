import Foundation

enum DevicePatchService {
    static func applyNOVAPackage(project: PatchProject) throws -> PatchTransactionReceipt {
        let target = try novaBundleIdentifier()
        guard project.allBundleIdentifiers == [target],
              !project.rules.isEmpty || !project.directories.isEmpty else {
            throw PatchPackageError.invalidBundleIdentifier
        }

        if let applied = latestReceipt(projectID: project.id, targetBundleID: target) {
            guard try PatchTransaction.requiredBundleIdentifiers(for: applied) == [target] else {
                throw PatchPackageError.invalidBundleIdentifier
            }
            return applied
        }
        if let prepared = latestPreparedReceipt(projectID: project.id, targetBundleID: target) {
            try restoreNOVAPackage(receipt: prepared)
        }

        return try apply(project: project)
    }

    static func restoreNOVAPackage(receipt: PatchTransactionReceipt) throws {
        let target = try novaBundleIdentifier()
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        guard bundleIDs == [target] else {
            throw PatchPackageError.invalidBundleIdentifier
        }
        try restore(receipt: receipt)
    }

    private static func novaBundleIdentifier() throws -> String {
        guard let bundleID = Bundle.main.bundleIdentifier,
              (try? PatchPathValidator.canonicalBundleIdentifier(bundleID)) == bundleID else {
            throw PatchPackageError.invalidBundleIdentifier
        }
        return bundleID
    }

    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        let bundleIDs = orderedBundleIdentifiers(in: project)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restore(receipt: PatchTransactionReceipt) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
            // Remote-only packages must not leave original backups or journals
            // behind after a successful CLEAN/restore.
            try? PatchTransaction.discardBackup(for: receipt)
        }
    }

    static func latestReceipt(projectID: UUID, targetBundleID: String? = nil) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(
            projectID: projectID,
            backupRoot: backupRoot,
            targetBundleID: targetBundleID
        )
    }

    static func latestPreparedReceipt(projectID: UUID, targetBundleID: String? = nil) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestPreparedReceipt(
            projectID: projectID,
            backupRoot: backupRoot,
            targetBundleID: targetBundleID
        )
    }

    static func receipt(
        projectID: UUID,
        transactionID: UUID,
        targetBundleID: String? = nil,
        includePrepared: Bool = false
    ) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.receipt(
            projectID: projectID,
            transactionID: transactionID,
            backupRoot: backupRoot,
            targetBundleID: targetBundleID,
            includePrepared: includePrepared
        )
    }

    static func transactionArtifactsExist(projectID: UUID, transactionID: UUID? = nil) -> Bool {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return false }
        return PatchTransaction.transactionArtifactsExist(
            projectID: projectID,
            transactionID: transactionID,
            backupRoot: backupRoot
        )
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]

        for bundleID in bundleIDs {
            guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID),
                  ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try operation(roots)
    }
}
