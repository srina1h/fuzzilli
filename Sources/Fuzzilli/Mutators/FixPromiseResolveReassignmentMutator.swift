

/// A mutator that specifically targets the pattern causing the crash described in the issue,

/// where `Promise.resolve` is reassigned before calling `Promise.allSettled`.

/// It removes the assignment to `Promise.resolve`.

public class FixPromiseResolveReassignmentMutator: BaseInstructionMutator {



    private let logger = Logger(withLabel: "FixPromiseResolveReassignmentMutator")



    public init() {

        super.init(name: "FixPromiseResolveReassignmentMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // We are looking for StoreProperty or StoreInstanceProperty instructions.

        return instr.op is StoreProperty || instr.op is StoreInstanceProperty

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        var propertyName: String? = nil

        var objectVar: Variable? = nil



        if let op = instr.op as? StoreProperty {

            propertyName = op.propertyName

            objectVar = instr.input(0) // The object being modified

        } else if let op = instr.op as? StoreInstanceProperty {

            propertyName = op.propertyName

            objectVar = instr.input(0) // The object being modified

        }



        // Check if the property being assigned is 'resolve'

        guard propertyName == "resolve", let objectVar = objectVar else {

            // Not the instruction we are looking for, bail out without making changes.

            // Need to re-emit the original instruction.

            b.adopt(instr)

            return

        }



        // Check if the object being modified is the Promise constructor.

        if isPromiseConstructor(objectVar, b) {

            logger.info("Found and removing problematic assignment to Promise.resolve: \(instr)")

            // Remove the instruction. Do not re-emit it.

            // The value being assigned (instr.input(1)) might become dead code,

            // which Fuzzilli's dead code elimination pass can handle later.

        } else {

            // It's a 'resolve' property assignment, but not on the Promise constructor. Keep it.

            b.adopt(instr)

        }

    }



    /// Helper function to determine if a variable likely holds the global Promise constructor.

    private func isPromiseConstructor(_ variable: Variable, _ b: ProgramBuilder) -> Bool {

        guard let definingInstruction = b.definition(of: variable) else {

            // Cannot determine the origin of the variable. Assume it's not Promise.

            return false

        }



        // Case 1: Direct loading of the Promise builtin

        if let loadBuiltin = definingInstruction.op as? LoadBuiltin, loadBuiltin.builtinName == "Promise" {

            return true

        }



        // Case 2: Loading the 'Promise' property from the global object

        if let loadProperty = definingInstruction.op as? LoadProperty, loadProperty.propertyName == "Promise" {

            // Check if the object loaded from is the global object.

            let globalObjectVar = definingInstruction.input(0)

            if let globalDef = b.definition(of: globalObjectVar),

               let loadBuiltin = globalDef.op as? LoadBuiltin,

               loadBuiltin.builtinName == "globalThis" { // Or other representations of global scope

                return true

            }

        }

         // Case 3: Loading the 'Promise' property from the global object (Instance Property)

        if let loadProperty = definingInstruction.op as? LoadInstanceProperty, loadProperty.propertyName == "Promise" {

            // Check if the object loaded from is the global object.

            let globalObjectVar = definingInstruction.input(0)

            if let globalDef = b.definition(of: globalObjectVar),

               let loadBuiltin = globalDef.op as? LoadBuiltin,

               loadBuiltin.builtinName == "globalThis" { // Or other representations of global scope

                return true

            }

        }





        // TODO: Could potentially add more checks if Promise is aliased,

        // but these cover the most common cases.



        return false

    }

}
