import Foundation

public class NewGlobalDiscardSourceMutator: BaseInstructionMutator {
    public init() {
        super.init(name: "NewGlobalDiscardSourceMutator")
    }
    
    public override func canMutate(_ instr: Instruction) -> Bool {
        // Check if this is a newGlobal call with discardSource: true
        if case .callFunction(let op) = instr.op.opcode {
            if instr.inputs[0].opcode == .loadString && instr.inputs[0].value == "newGlobal" {
                for arg in instr.inputs.dropFirst() {
                    if case .objectLiteral(let properties) = arg.op {
                        for prop in properties {
                            if prop.name == "discardSource" {
                                if case .boolean(let value) = prop.value.op {
                                    return value == true
                                }
                            }
                        }
                    }
                }
            }
        }
        return false
    }
    
    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        // Replace the newGlobal call with discardSource: false
        if case .callFunction(let op) = instr.op.opcode {
            var newArguments = instr.inputs.dropFirst()
            for (index, arg) in newArguments.enumerated() {
                if case .objectLiteral(let properties) = arg.op {
                    var newProperties = properties
                    for (propIndex, prop) in properties.enumerated() {
                        if prop.name == "discardSource" {
                            newProperties[propIndex] = ObjectLiteralProperty(name: "discardSource", value: b.loadBool(false))
                        }
                    }
                    newArguments[index] = b.createObjectLiteral(with: newProperties)
                }
            }
            b.callFunction(instr.inputs[0], withArgs: Array(newArguments))
        }
    }
}