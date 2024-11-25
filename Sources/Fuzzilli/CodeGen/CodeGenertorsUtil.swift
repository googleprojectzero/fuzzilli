import Foundation

func randomLabelBreak(_ b: ProgramBuilder) {
    if b.isLoopStaNotEmpty() {
        if probability(0.2) {
            if probability(0.5) {
                b.loopLabelBreak(b.randomLabel())
            } else {
                b.loopLabelContinue(b.randomLabel())
            }
        }
    }
}

func randomloadLabel(_ b: ProgramBuilder) -> Bool {
    let labelValue = b.loadString(String(UUID().uuidString.prefix(6)))
    let makelabel = probability(0.2)
    if makelabel {
        b.loadLabel(labelValue)
        b.pushLabel(labelValue)
    }
    return makelabel
}

func popLabelIfMake(_ b: ProgramBuilder, _ makelabel: Bool) {
    if makelabel {
        b.popLabel()
    }
}
