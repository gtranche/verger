import Metal

/// La famille Metal de la carte graphique de ce Mac, comme Cidre la lit
/// (tests/machine.sh, fait `famille_gpu`) : la plus haute `MTLGPUFamilyApple<N>`
/// que Metal reconnait. 7 = M1, 8 = M2, 9 = M3 et M4.
enum MetalFamily {
    static let current: Int? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let found = (1...30).filter { n in
            MTLGPUFamily(rawValue: 1000 + n).map(device.supportsFamily) ?? false
        }
        return found.max()
    }()
}
