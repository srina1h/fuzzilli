

/// A mutator that transforms a specific `for...in` loop pattern over a large TypedArray

/// into a standard `for` loop with checks, targeting a specific crash scenario.

public class ForInToForLoopMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "ForInToForLoopMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if the instruction is BeginForIn

        guard instr.op is BeginForIn else {

            return false

        }



        // We need to look ahead slightly to see if the next instruction is EndForIn,

        // indicating an empty loop body, which matches the crash pattern.

        // This requires access to the program or builder state, which isn't directly

        // available in `canMutate`. We'll do a preliminary check here and a more

        // thorough check in `mutate`.

        return true

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        // Ensure the instruction is indeed BeginForIn

        guard instr.op is BeginForIn else {

            return

        }



        // Find the index of the instruction we are mutating.

        guard let index = b.indexOf(instr) else {

            logger.error("Instruction \(instr) not found in program")

            return

        }



        // Check if the next instruction is EndForIn (empty loop body)

        guard index + 1 < b.prog.size, b.prog[index + 1].op is EndForIn else {

            // The loop body is not empty, this mutator doesn't apply to this specific pattern.

            // We could potentially make it more general, but for this specific request,

            // we target the empty loop body pattern.

            return

        }



        // Check if the iterated object comes from a TypedArray constructor.

        // This is a heuristic based on the provided positive test case.

        let iteratedVar = instr.input(0)

        guard let creationInstr = b.definition(of: iteratedVar),

              creationInstr.op is Construct,

              creationInstr.numInputs > 0,

              let constructorVar = b.definition(of: creationInstr.input(0)),

              constructorVar.op is LoadBuiltin,

              let builtinName = (constructorVar.op as? LoadBuiltin)?.builtinName,

              builtinName.contains("Array") // Heuristic: Float64Array, Int32Array, etc.

        else {

            // The iterated object doesn't seem to be a TypedArray created in a way

            // that matches the crash pattern.

            return

        }



        // If all checks pass, perform the transformation.

        b.trace("Mutating \(instr) at #\(index) into a standard for loop")



        // We will replace the BeginForIn and EndForIn instructions.

        // Mark the original instructions for removal later (Fuzzilli handles this).

        b.remove(instr)

        b.remove(b.prog[index + 1]) // Remove the corresponding EndForIn



        // --- Start Emitting the new code ---



        // Keep the original ArrayBuffer and TypedArray creation (they are before the loop)



        // Create and initialize helper variables before the loop

        let countVar = b.createVariable(ofType: .integer)

        b.loadInt(0, output: countVar)



        let lastValueVar = b.createVariable(ofType: .unknown) // Type could be more specific if needed

        b.loadInt(0, output: lastValueVar) // Initialize with a simple value



        // Create the loop index variable

        let indexVar = b.createVariable(ofType: .integer)

        b.loadInt(0, output: indexVar) // Initialize index 'i' to 0



        // Get the length of the typed array

        let lengthVar = b.getProperty("length", of: iteratedVar)



        // Begin the standard for loop: for (let i = 0; i < v21.length; i++)

        // Fuzzilli's BeginForLoop takes initial value implicitly from indexVar initialization

        let one = b.loadInt(1)

        b.beginForLoop(indexVar, .lessThan, lengthVar, .Add, one)



        // Loop Body Start

        // Access the element: lastValue = v21[i];

        let elementVar = b.getElement(indexVar, of: iteratedVar)

        b.reassign(lastValueVar, to: elementVar)



        // Increment count: count++;

        b.unary(.PostInc, countVar) // Or use BinaryOp Add + Reassign if Unary(.PostInc) isn't suitable



        // Break condition: if (count > 1000) { break; }

        let limitVar = b.loadInt(1000)

        let conditionVar = b.compare(countVar, limitVar, with: .greaterThan)

        b.beginIf(conditionVar)

        b.loopBreak()

        b.endIf()



        // Loop Body End

        b.endForLoop()



        // Post-loop check: if (count <= 1000) { throw ... }

        // Need to reload limit or ensure it's still valid depending on Fuzzili scoping

        let checkLimitVar = b.loadInt(1000) // Reload for safety or use existing if scope allows

        let checkConditionVar = b.compare(countVar, checkLimitVar, with: .lessThanOrEqual)

        b.beginIf(checkConditionVar)

        let errorMessage = b.loadString("Loop did not execute as expected")

        let errorConstructor = b.loadBuiltin("Error")

        let errorObj = b.construct(errorConstructor, withArgs: [errorMessage])

        b.throwException(errorObj)

        b.endIf()



        // --- End Emitting the new code ---

    }

}
