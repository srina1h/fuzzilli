

/// A highly specific mutator designed to transform a particular crashing program

/// (related to SpiderMonkey commit 6d5114b3ba4e) into a non-crashing variant.

///

/// It targets the following pattern within a function's loop:

/// ```javascript

///   someString.slice(someArg).search(undefined);

/// ```

/// And transforms it into:

/// ```javascript

///   let result = 0;

///   // ... loop ...

///   result += someString.slice(someArg).search("neg");

///   // ... end loop ...

///   return result;

/// ```

/// This avoids a crash presumably caused by type feedback issues with `search(undefined)`

/// after the `slice` result changes type based on the input argument across loop iterations.

public class SpiderMonkeySpecificSearchUndefinedMutator: BaseMutator {



    private let logger = Logger(withLabel: "SpiderMonkeySpecificSearchUndefinedMutator")



    public init() {

        super.init(name: "SpiderMonkeySpecificSearchUndefinedMutator")

    }



    // Helper to check if a variable comes directly from LoadUndefined

    // Note: We check against the original program's code structure before modifications.

    private func isFromLoadUndefined(_ v: Variable, in code: Code) -> Bool {

        guard let producer = code.producer(of: v) else { return false }

        return producer.op is LoadUndefined

    }



    // Helper to check if a variable comes directly from a specific CallMethod

    // Note: We check against the original program's code structure before modifications.

    private func isFromCallMethod(_ v: Variable, methodName: String, in code: Code) -> Bool {

        guard let producer = code.producer(of: v) else { return false }

        guard let callOp = producer.op as? CallMethod else { return false }

        return callOp.methodName == methodName

    }



    public override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {



        var targetSearchCallIndex: Int? = nil

        var targetBeginFunctionIndex: Int? = nil

        var targetEndFunctionIndex: Int? = nil



        // Phase 1: Find the specific instruction indices in the original program

        // We are looking for the first function definition containing the specific

        // `slice(...).search(undefined)` pattern.

        for i in 0..<program.code.count {

            let instr = program.code[i]



            // Track the outermost function definition

            if instr.op is BeginFunction {

                 if targetBeginFunctionIndex == nil {

                    targetBeginFunctionIndex = i

                 }

            } else if instr.op is EndFunction {

                 // Find the EndFunction matching the BeginFunction we tracked

                 if let beginIdx = targetBeginFunctionIndex,

                    targetEndFunctionIndex == nil,

                    instr.beginFunction?.index == beginIdx {

                     targetEndFunctionIndex = i

                 }

            }



            // Look for the target CallMethod instruction

            if let callOp = instr.op as? CallMethod,

               callOp.methodName == "search",

               instr.numInputs == 2 {



               let objVar = instr.input(0)

               let argVar = instr.input(1)



               // Check the producer context using the original program structure

               if isFromCallMethod(objVar, methodName: "slice", in: program.code) &&

                  isFromLoadUndefined(argVar, in: program.code) {



                  // Ensure this call is within the function we are tracking

                  if let beginFuncIdx = targetBeginFunctionIndex, targetEndFunctionIndex == nil {

                     // Found the potential target instruction. Store its index.

                     // If multiple exist, this mutator will target the first one found.

                     if targetSearchCallIndex == nil {

                         targetSearchCallIndex = i

                     }

                  }

               }

            }

        }



        // Phase 2: Verify that all necessary indices were found

        guard let beginFuncIdx = targetBeginFunctionIndex,

              let endFuncIdx = targetEndFunctionIndex,

              let searchCallIdx = targetSearchCallIndex,

              searchCallIdx > beginFuncIdx, // Sanity check: search call is after function begin

              searchCallIdx < endFuncIdx     // Sanity check: search call is before function end

        else {

            // logger.info("Required pattern structure not found or indices invalid.")

            return nil // Indicate mutation was not possible

        }



        // Phase 3: Rebuild the program with the targeted modifications

        b.adopting(from: program) {

            // It's crucial to get original instruction details *before* modifying the builder,

            // as indices might shift.

            let originalSearchInstr = program.code[searchCallIdx]

            let sliceResultVar = originalSearchInstr.input(0) // The variable holding the output of slice()

            let searchOutputVar = originalSearchInstr.output // The original output variable of search()



            // --- Modifications ---



            // 1. Insert `let result = 0;` right after the BeginFunction instruction.

            //    Use b.loadInt to create the constant and its variable.

            let resultVar = b.loadInt(0)

            //    Insert the LoadInteger instruction at the correct position.

            //    Fuzzilli's builder handles index adjustments for subsequent operations.

            b.insert(Instruction(LoadInteger(value: 0), output: resultVar), at: beginFuncIdx + 1)

            //    Mark the variable as mutable 'let' by reassigning it (though not strictly necessary

            //    if only used as input/output for operations like BinaryOp). For clarity:

            b.reassign(resultVar, to: resultVar)





            // 2. Replace the `search(undefined)` call with `search("neg")`.

            //    Find the instruction in the *current* builder state using its original index.

            guard let currentSearchInstr = b.find(instruction: searchCallIdx) else {

                 logger.error("Cannot find original search instruction in builder after insertion. Aborting.")

                 b.reset() // Invalidate builder state

                 return

            }

            //    Create the "neg" string constant.

            let negString = b.loadString("neg")

            //    Perform the replacement. Use the *original* output variable (`searchOutputVar`).

            //    The builder's `replace` operation updates the IR.

            b.callMethod("search", on: sliceResultVar, withArgs: [negString], output: searchOutputVar, replacing: currentSearchInstr)





            // 3. Insert `result = result + searchResult` *after* the now-modified search call.

            //    The index of the modified search call is still `currentSearchInstr.index`.

            let addOp = BinaryOperation(.Add)

            //    Insert the BinaryOp instruction. The output (`resultVar`) overwrites the previous value.

            b.insert(Instruction(BinaryOp(addOp), inputs: [resultVar, searchOutputVar], output: resultVar), at: currentSearchInstr.index + 1)





            // 4. Insert `return result;` just *before* the corresponding EndFunction instruction.

            //    Find the EndFunction instruction in the *current* builder state.

            guard let currentEndFuncInstr = b.find(instruction: endFuncIdx) else {

                 logger.error("Cannot find original EndFunction instruction in builder after insertions. Aborting.")

                 b.reset() // Invalidate builder state

                 return

            }

            //    Insert the Return instruction.

            b.insert(Instruction(Return(), input: resultVar), at: currentEndFuncInstr.index)



            // --- End Modifications ---



            logger.info("Successfully applied \(self.name) mutation.")



        } // End adopting block (builder context is automatically managed)



        // Finalize the builder to get the new Program object

        return b.finalize()

    }

}
