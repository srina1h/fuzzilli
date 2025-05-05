import Foundation



// This mutator specifically targets the pattern `Reflect.apply(obj.method, thisArg, argsArray)`

// and replaces it with a direct method call `obj.method()`, mirroring the transformation

// from the provided positive (crashing) test case to the negative (non-crashing) one.

// It assumes the arguments passed via `Reflect.apply` are not essential for the basic

// functionality or that replacing the call with a direct one (often with no arguments

// as in the example) circumvents the crash condition.

public class ReflectApplyToDirectCallMutator: BaseInstructionMutator {



    private let logger = Logger(withLabel: "ReflectApplyToDirectCallMutator")



    public init() {

        super.init(name: "ReflectApplyToDirectCallMutator")

    }



    // Keep canMutate simple: check instruction type and minimum number of inputs.

    // Reflect.apply requires at least 3 inputs: callee, target function, thisArg.

    public override func canMutate(_ instr: Instruction) -> Bool {

        return instr.op is CallFunction && instr.numInputs >= 3

    }



    // Perform detailed checks using the ProgramBuilder and mutate if the pattern matches.

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Check 1: Is the called function literally Reflect.apply?

        guard let callee = instr.input(0),

              let calleeInstr = b.findDef(callee),

              calleeInstr.op is LoadProperty,

              let loadApplyOp = calleeInstr.op as? LoadProperty,

              loadApplyOp.propertyName == "apply",

              let reflectObj = calleeInstr.input(0),

              let reflectDef = b.findDef(reflectObj),

              reflectDef.op is LoadBuiltin,

              let loadBuiltinOp = reflectDef.op as? LoadBuiltin,

              loadBuiltinOp.builtinName == "Reflect"

        else {

            // Not a Reflect.apply call. Re-emit the original instruction.

            b.adopt(instr)

            return

        }



        // Check 2: Is the first argument (the target function) derived from loading a property?

        // This corresponds to the obj.method part.

        guard let targetFuncVar = instr.input(1),

              let targetFuncInstr = b.findDef(targetFuncVar),

              targetFuncInstr.op is LoadProperty,

              let loadMethodOp = targetFuncInstr.op as? LoadProperty

        else {

            // The target function is not a simple property load. Re-emit the original instruction.

            b.adopt(instr)

            return

        }



        // Pattern matched: Reflect.apply(obj.method, ...)

        // Perform the mutation.



        let objectVar = targetFuncInstr.input(0)   // The object variable (e.g., 'y' in the example)

        let methodName = loadMethodOp.propertyName // The method name (e.g., 'toString')



        // Based on the negative test case, replace with a direct call with no arguments.

        let directCallArgs: [Variable] = []



        // Replace the original CallFunction instruction with a CallMethod instruction.

        b.callMethod(methodName, on: objectVar, withArgs: directCallArgs)



        // The original instruction (instr) is intentionally discarded and replaced.

    }

}
