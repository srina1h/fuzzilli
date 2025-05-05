

// Specific mutator to address the dumpStencil lineNumber issue by

// replacing `obj.lineNumber = func` with `obj.lineNumber = 1`.

// This transformation aims to convert the positive (crashing) test case

// into the negative (non-crashing) test case provided in the prompt.

public class FixDumpStencilLineNumberMutator: BaseInstructionMutator {



    public init() {

        // Give the mutator a descriptive name.

        super.init(name: "FixDumpStencilLineNumberMutator")

    }



    /// Determines if the mutator should attempt to mutate this instruction.

    /// We are specifically looking for instructions that store a property named "lineNumber".

    /// The check for whether the stored value is a function is deferred to the `mutate` method,

    /// as `canMutate` doesn't have easy access to the variable's definition context.

    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if the operation is StoreProperty and the propertyName is "lineNumber".

        guard instr.op is StoreProperty,

              instr.op.properties["propertyName"] == "lineNumber",

              instr.numInputs == 2 else { // StoreProperty expects obj and value inputs

            return false

        }

        // It matches the basic structure, so potentially mutable.

        return true

    }



    /// Performs the mutation.

    /// If the instruction is `StoreProperty 'lineNumber', obj, value` and `value` is likely

    /// a function variable (defined by LoadBuiltin or CreateClosure), this method

    /// replaces the instruction with `LoadInt 1` followed by `SetProperty 'lineNumber', obj, 1`.

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Double-check preconditions established by canMutate.

        assert(instr.op is StoreProperty && instr.op.properties["propertyName"] == "lineNumber")

        assert(instr.numInputs == 2)



        let objectVar = instr.input(0) // The object being modified

        let valueVar = instr.input(1)  // The value being assigned to lineNumber



        // Crucial check: Verify if the value being assigned is likely a function.

        // We look at how `valueVar` was defined in the program history available via the builder.

        guard let valueDefinition = b.definition(of: valueVar),

              valueDefinition.op is LoadBuiltin || valueDefinition.op is CreateClosure else {

            // If `valueVar` was not defined by LoadBuiltin or CreateClosure,

            // it's unlikely to be the specific function assignment causing the crash.

            // In this case, we preserve the original instruction to avoid incorrect mutations.

            b.adopt(instr)

            return

        }



        // If we reach here, the instruction matches the problematic pattern:

        // `someObject.lineNumber = someFunction;`

        b.trace("Applying FixDumpStencilLineNumberMutator: Replacing StoreProperty [lineNumber]=<function>")



        // 1. Create the integer constant '1'. This will be the new value for lineNumber.

        let constantOneVar = b.loadInt(1)



        // 2. Replace the original StoreProperty instruction with a SetProperty instruction.

        //    SetProperty performs the assignment `objectVar.lineNumber = constantOneVar`.

        //    This effectively changes the behavior from assigning a function to assigning the integer 1.

        b.setProperty(of: objectVar, to: constantOneVar, named: "lineNumber")



        // By not calling `b.adopt(instr)`, the original `StoreProperty` instruction (`instr`)

        // is discarded and replaced in the output program by the `LoadInt` and `SetProperty`

        // instructions generated above.

    }

}
