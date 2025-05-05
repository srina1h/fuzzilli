

public class SpecificDateTimeCrashFixer: Mutator {

    let name = "SpecificDateTimeCrashFixer"



    // This mutator attempts to transform a specific crashing JavaScript program

    // involving Intl.DateTimeFormat and a large string pattern into a non-crashing

    // version by applying targeted FuzzIL instruction changes. It looks for:

    // 1. String.prototype.repeat(65536) within a function scope.

    // 2. Construction of an object via a variable likely holding Intl.DateTimeFormat.

    // 3. A call to 'formatRangeToParts' with integer arguments 0 and 1.

    // It modifies these specific instructions based on the negative test case provided.

    // NOTE: This is highly specific to the provided example and its likely FuzzIL

    //       representation. It does not implement the JavaScript-level robustness

    //       checks (try-catch, typeof) shown in the negative example code.

    func mutate(_ program: Program, using fuzzer: Fuzzer) -> Program? {

        var changed = false

        let b = fuzzer.makeBuilder()



        // State variables to identify the target pattern components

        var f7Context = false // Tracks if we are inside the relevant function scope (heuristically)

        var v_DateTimeFormat_ctor: Variable? = nil // Variable holding the DateTimeFormat constructor

        var v_DateTimeFormat_instance: Variable? = nil // Variable holding the constructed instance



        // Indices of the instructions to be modified

        var repeatLoadIntIndex: Int? = nil // Index of the LoadInteger(65536) instruction

        var constructIndex: Int? = nil // Index of the Construct instruction

        var callMethodIndex: Int? = nil // Index of the formatRangeToParts CallMethod instruction



        // --- Pass 1: Identify the target instructions and variables ---

        for (index, instr) in program.code.enumerated() {



            // Track function scope (simple heuristic)

            if instr.op is BeginFunction { f7Context = true }

            if instr.op is EndFunction { f7Context = false }



            // 1. Find LoadInteger(65536) that is used as the argument to String.prototype.repeat

            if f7Context, let loadInt = instr.op as? LoadInteger, loadInt.value == 65536 {

                // Check if the next instructions are LoadProperty("repeat") and CallMethod using the integer

                if index + 2 < program.code.count,

                   let loadProp = program.code[index + 1].op as? LoadProperty, loadProp.propertyName == "repeat",

                   program.code[index + 2].op is CallMethod, // Check op type is CallMethod

                   let callInstr = program.code[index + 2], // Safe to access now

                   callInstr.input(0) == program.code[index + 1].output, // Method input matches LoadProperty output

                   callInstr.numInputs == 3, // Expecting method, this, arg1

                   callInstr.input(2) == instr.output // Arg1 matches the LoadInteger output

                {

                    repeatLoadIntIndex = index

                }

            }



            // 2. Find the variable holding the DateTimeFormat constructor (heuristically by property name)

            if let loadProp = instr.op as? LoadProperty, loadProp.propertyName == "DateTimeFormat" {

                // Assume this is the correct variable for this specific case

                v_DateTimeFormat_ctor = instr.output

            }



            // 3. Find the Construct instruction using the identified DateTimeFormat constructor variable

            //    and record the resulting instance variable.

            if let constructOp = instr.op as? Construct, instr.numInputs > 0, instr.input(0) == v_DateTimeFormat_ctor {

                 // Assume this is the target construction call

                 v_DateTimeFormat_instance = instr.output

                 constructIndex = index

            }



            // 4. Find the CallMethod for formatRangeToParts on the instance, with specific integer arguments 0, 1

            if let callOp = instr.op as? CallMethod, instr.numInputs == 4, instr.input(1) == v_DateTimeFormat_instance {

                 // Check if the method name is 'formatRangeToParts' (by checking the defining instruction of the method variable)

                 if let loadPropIdx = instr.input(0).definingInstructionIndex, loadPropIdx < program.code.count,

                    let loadProp = program.code[loadPropIdx].op as? LoadProperty,

                    loadProp.propertyName == "formatRangeToParts" {

                     // Check if the arguments are the result of LoadInteger 0 and LoadInteger 1

                     if let arg1Idx = instr.input(2).definingInstructionIndex, arg1Idx < program.code.count,

                        let arg2Idx = instr.input(3).definingInstructionIndex, arg2Idx < program.code.count,

                        let loadInt1 = program.code[arg1Idx].op as? LoadInteger, loadInt1.value == 0,

                        let loadInt2 = program.code[arg2Idx].op as? LoadInteger, loadInt2.value == 1 {

                         callMethodIndex = index

                     }

                 }

            }

        }



        // --- Check if all necessary components of the pattern were found ---

        guard let repeatIdx = repeatLoadIntIndex,

              let constructIdx = constructIndex,

              let callIdx = callMethodIndex,

              let ctorVar = v_DateTimeFormat_ctor, // Ensure constructor var was found

              let instanceVar = v_DateTimeFormat_instance // Ensure instance var was found

        else {

            // The specific pattern was not found in the program, cannot apply this mutation.

            return nil

        }



        // --- Pass 2: Build the modified program ---

        b.adopting(from: program) { // Use adopting builder to handle context and variable mapping

            for (index, instr) in program.code.enumerated() {

                if index == repeatIdx {

                    // Apply modification 1: Change the repeat count

                    b.loadInt(32766) // Replace LoadInteger(65536)

                    changed = true

                } else if index == constructIdx {

                    // Apply modification 2: Change the Construct arguments

                    let originalInstr = program.code[constructIdx]

                    let undef = b.loadUndefined()

                    let options = b.createObject(with: [:])

                    // Reconstruct using the original constructor variable (ctorVar) but with new arguments

                    b.construct(ctorVar, withArgs: [undef, options], reassign: originalInstr.isReassign)

                    changed = true

                } else if index == callIdx {

                    // Apply modification 3: Change the CallMethod arguments for formatRangeToParts

                    let originalInstr = program.code[callIdx]

                    let methodVar = originalInstr.input(0) // The variable holding the formatRangeToParts method



                    // Create 'new Date(0)' and 'new Date(1)'

                    let dateConstructor = b.loadBuiltin("Date")

                    let zero = b.loadInt(0)

                    let one = b.loadInt(1)

                    let date0 = b.construct(dateConstructor, withArgs: [zero])

                    let date1 = b.construct(dateConstructor, withArgs: [one])



                    // Call the method (methodVar) on the original instance (instanceVar) with the new Date arguments

                    b.callMethod(methodVar, on: instanceVar, withArgs: [date0, date1], reassign: originalInstr.isReassign)

                    changed = true

                } else {

                    // Copy all other instructions unmodified

                    b.adopt(instr)

                }

            }

        } // End adopting block



        // Return the modified program only if changes were actually made

        return changed ? b.finalize() : nil

    }

}
