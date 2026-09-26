import Testing
@testable import MatindCore

@Suite("服务实例阶段")
struct ServiceLifecycleTests {
    @Test("回声模块按安装、启用、停用、卸载走完")
    func echoCompletesLifecycle() {
        var phase = ServiceInstancePhase.available
        let steps: [ServiceCommand] = [
            .beginInstall, .acceptPackage, .enable, .finishStart, .stop, .beginRemoval, .finishRemoval
        ]
        let expected: [ServiceInstancePhase] = [
            .installing, .installed, .starting, .running, .stopped, .removing, .available
        ]
        for (command, destination) in zip(steps, expected) {
            let transition = ServiceLifecycle.next(phase: phase, command: command)
            #expect(transition?.phase == destination)
            phase = transition?.phase ?? phase
        }
        #expect(phase == .available)
    }

    @Test("校验失败或取消安装都回到可安装")
    func rejectedInstallReturnsToAvailable() {
        let rejected = ServiceLifecycle.next(phase: .installing, command: .rejectPackage)
        let cancelled = ServiceLifecycle.next(phase: .installing, command: .cancelInstall)
        #expect(rejected?.phase == .available)
        #expect(cancelled?.phase == .available)
    }

    @Test("未安装时不能启用，运行中不能卸载")
    func illegalCommandsAreRefused() {
        #expect(ServiceLifecycle.next(phase: .available, command: .enable) == nil)
        #expect(ServiceLifecycle.next(phase: .running, command: .beginRemoval) == nil)
        #expect(ServiceLifecycle.commands(for: .running) == [.stop])
    }

    @Test("摘要对不上的安装包被拒绝")
    func unlistedDigestIsRejected() {
        #expect(PlatformModuleTrust.verify(moduleId: "matind.echo", version: "1.0.0", digest: "echo-1.0.0") == .trusted)
        #expect(PlatformModuleTrust.verify(moduleId: "matind.echo", version: "1.0.0", digest: "tampered") == .rejected)
    }
}
