import Foundation

public class NewGlobalDiscardSourceMutator: BaseInstructionMutator {
    public init() {
        super.init(name: "NewGlobalDiscardSourceMutator")
    }
    
    public override func canMutate(_ instr: Instruction) -> Bool {
        // Check if this is a newGlobal call with discardSource: true
        if case .callFunction(let op) = instr.op.opcode {
            if case .loadString(let loadOp) = instr.inputs[0].op.opcode, loadOp.value == "newGlobal" {
                for arg in instr.inputs.dropFirst() {
                    if case .objectLiteral(let properties) = arg.op.opcode {
                        for prop in properties {
                            if prop.name == "discardSource" {
                                if case .loadBoolean(let boolOp) = prop.value.op.opcode {
                                    return boolOp.value == true
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
                if case .objectLiteral(let properties) = arg.op.opcode {
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