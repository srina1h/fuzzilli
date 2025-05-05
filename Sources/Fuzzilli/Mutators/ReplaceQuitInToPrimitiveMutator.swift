

/// A mutator specifically designed to replace the assignment of the 'quit' builtin

/// to Symbol.toPrimitive with an assignment of a safe inline function.

/// This targets the specific crash pattern where `obj[Symbol.toPrimitive] = quit`

/// leads to an assertion failure when the object is used in certain operations like

/// being the 'cause' property for bindToAsyncStack.

/// It transforms code like:

///   v_quit = LoadBuiltin 'quit'

///   ...

///   StoreProperty 'Symbol.toPrimitive' of v0 to v_quit

/// Into:

///   BeginFunction ... => v_safeFunc

///   StoreProperty 'Symbol.toPrimitive' of v0 to v_safeFunc

public class ReplaceQuitInToPrimitiveMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "ReplaceQuitInToPrimitiveMutator")

    }



    /// Determines if the mutator can be applied to a given instruction.

    /// We are looking for `StoreProperty 'Symbol.toPrimitive'`.

    /// A more robust check would verify that the value being stored originates

    /// from `LoadBuiltin 'quit'`, but this requires program analysis beyond

    /// the local scope of BaseInstructionMutator. We proceed assuming this

    /// instruction shape is a strong indicator for the target pattern.

    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if it's a StoreProperty instruction targeting 'Symbol.toPrimitive'.

        guard let storeOp = instr.op as? StoreProperty,

              storeOp.propertyName == "Symbol.toPrimitive",

              instr.numInputs == 2 else { // Requires object and value inputs

            return false

        }

        // Assume this pattern is specific enough for the targeted transformation.

        return true

    }



    /// Performs the mutation.

    /// Replaces `someObj[Symbol.toPrimitive] = quit` (or whatever value was there) with

    /// `someObj[Symbol.toPrimitive] = function(hint) { if (hint === 'number') return 42; return "safe string"; }`

    /// based on the negative test case structure.

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        guard let storeOp = instr.op as? StoreProperty, // Ensured by canMutate

              storeOp.propertyName == "Symbol.toPrimitive",

              instr.numInputs == 2 else {

            // Should not be reached if canMutate is correct.

            return

        }



        let objectVar = b.adopt(instr.input(0)) // The object being modified (e.g., v0)

        // let originalValueVar = instr.input(1) // The original value (e.g., variable holding 'quit') - unused in replacement



        b.trace("Applying ReplaceQuitInToPrimitiveMutator to replace assignment to \(objectVar)[\(storeOp.propertyName)]")



        // --- Build the replacement function ---

        // function(hint) {

        //   if (hint === 'number') {

        //     return 42;

        //   }

        //   return "safe string";

        // }

        let hintParam = b.loadParameter(index: 0)

        b.beginFunction(parameters: [.plain("hint")])



        // Condition: hint === 'number'

        let numberString = b.loadString("number")

        let condition = b.compare(hintParam, numberString, with: .strictEqual)



        // If branch: return 42

        b.beginIf(condition)

        let num42 = b.loadInt(42)

        b.doReturn(value: num42)

        b.endIf()



        // Else branch (implicit): return "safe string"

        let safeString = b.loadString("safe string")

        b.doReturn(value: safeString)



        let safeFunctionVar = b.endFunction() // Variable holding the newly created function



        // --- Replace the original StoreProperty instruction ---

        // Emit the new StoreProperty instruction, assigning the new safe function.

        b.storeProperty(propertyName: storeOp.propertyName, on: objectVar, value: safeFunctionVar)



        b.trace("Replaced assignment to Symbol.toPrimitive with a safe function: \(objectVar)[\(storeOp.propertyName)] = \(safeFunctionVar)")

        // The original instruction `instr` is effectively replaced by the actions performed using the builder `b`.

    }

}
