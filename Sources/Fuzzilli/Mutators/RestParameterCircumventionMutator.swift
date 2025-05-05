

// A mutator designed to circumvent potential optimizations for rest parameters

// by either increasing the number of arguments passed at call sites or

// ensuring the rest parameter array is accessed within the function body.

// This targets scenarios like the one described where optimizations for 0-2

// rest arguments might be bypassed by providing more arguments or by forcing

// the materialization/use of the rest parameter array (e.g., accessing .length).

public class RestParameterCircumventionMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "RestParameterCircumventionMutator", maxSimultaneousMutations: 1)

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Target CallFunction instructions

        if instr.op is CallFunction {

            // Potentially check if the function signature might involve rest parameters,

            // but for broader application, initially allow mutation attempt on any call.

            return true

        }



        // Target instructions inside functions that might use a rest parameter.

        // We'll check the context (am I inside a function with rest params?)

        // and if the instruction uses the rest param variable inside mutate().

        if instr.hasInputs {

             // Further checks needed in mutate()

             return true

        }



        return false

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        if instr.op is CallFunction {

            mutateCallSite(instr, b)

        } else if instr.hasInputs && b.currentFunctionSignature?.hasRestParameter == true {

            // Only attempt usage mutation if we are indeed inside a function

            // known to have rest parameters.

            mutateRestParameterUsage(instr, b)

        } else {

            // Default action: re-append the original instruction if no mutation is applicable

             b.append(instr)

        }

    }



    /// Attempts to add more arguments to a function call, specifically targeting

    /// scenarios where a function with rest parameters might be called with few arguments.

    private func mutateCallSite(_ instr: Instruction, _ b: ProgramBuilder) {

        guard let call = instr.op as? CallFunction else {

            b.append(instr)

            return

        }



        let callee = instr.input(0)

        // In a real scenario, we'd ideally inspect the callee's signature more deeply.

        // Fuzzilli's type system might help determine if it expects rest parameters

        // and how many formal parameters it has.

        // For this mutator, we apply a heuristic: if a call has relatively few

        // arguments, try adding more, hoping to exceed the 0-2 rest arg count.



        // Heuristic: Consider calls with 1 to 4 total arguments (callee + actual args)

        // as candidates for having few (0-2) rest arguments supplied.

        // Example: g(i, 1, 2) has 4 inputs (g, i, 1, 2). numInputs = 4. Formal params = 1. Rest args = 2.

        // Example: g(i) has 2 inputs (g, i). Formal params = 1. Rest args = 0.

        if instr.numInputs >= 2 && instr.numInputs <= 4 {

            var inputs = b.adopt(instr.inputs)



            // Add 3-5 random arguments to likely push past the 2-element optimization point.

            let numToAdd = Int.random(in: 3...5)

            var addedCount = 0

            for _ in 0..<numToAdd {

                // Try adding various types of constants or existing variables

                if let arg = b.randomVariable(ofType: .primitive) ?? b.randomVariable() {

                     inputs.append(arg)

                     addedCount += 1

                } else {

                    // Fallback to simple primitives if no suitable variable found

                    switch Int.random(in: 0...2) {

                    case 0: inputs.append(b.loadInt(Int64.random(in: 0...10)))

                    case 1: inputs.append(b.loadFloat(Double.random(in: 0...10)))

                    case 2: inputs.append(b.loadBool(Bool.random()))

                    default: break // Should not happen

                    }

                     addedCount += 1

                }

            }



            if addedCount > 0 {

                b.append(Instruction(call, inputs: inputs))

                return // Mutation successful

            }

        }



        // Default: Re-append original instruction if no mutation happened

        b.append(instr)

    }



    /// Attempts to change how a rest parameter variable is used within its function,

    /// specifically by accessing its 'length' property.

    private func mutateRestParameterUsage(_ instr: Instruction, _ b: ProgramBuilder) {

        guard let signature = b.currentFunctionSignature, signature.hasRestParameter else {

            // Should not happen due to check in mutate(), but defensive check.

            b.append(instr)

            return

        }



        // Identify the rest parameter variable. It's the last parameter.

        // Parameters are inputs to the CodeBlock instruction.

        guard let codeBlock = b.currentCodeBlock, codeBlock.parameters.count > signature.numParameters else {

             b.append(instr)

             return

        }

        let restParamVar = codeBlock.parameters[signature.numParameters]



        var mutated = false

        // Check if the instruction uses the rest parameter variable directly as input.

        for i in 0..<instr.numInputs {

            if instr.input(i) == restParamVar {

                // Found a usage of the rest parameter variable.

                // Replace this usage with its length.

                // Example: Change `h(arr)` to `let len = arr.length; h(len)`



                // Ensure we don't try this on property accessors *of* the rest param already

                if instr.op is GetProperty || instr.op is SetProperty || instr.op is CallMethod {

                   if i == 0 { // if the rest parameter is the object being accessed

                       continue // Skip, already accessing a property/method

                   }

                }



                let lengthVar = b.getProperty(restParamVar, "length")



                // Replace the original restVar input with lengthVar

                var newInputs = b.adopt(instr.inputs)

                newInputs[i] = lengthVar

                b.append(Instruction(instr.op, inputs: newInputs, flags: instr.flags))

                mutated = true

                break // Mutate only the first occurrence found for simplicity

            }

        }



        if !mutated {

            b.append(instr) // No mutation occurred

        }

    }

}
