

// A mutator that attempts to prevent crashes related to revoked proxies

// by removing the first encountered 'revoke' method call.

// This specifically targets the scenario where `proxy.revoke()` is called

// before the proxy object is used, potentially leading to a crash or TypeError.

// By removing the `revoke()` call, the proxy remains active, thus changing

// the program's behavior from the potentially crashing positive case

// to the non-crashing negative case described.

public class RemoveRevokeCallMutator: BaseMutator {



    public init() {

        super.init(name: "RemoveRevokeCallMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        var revokeInstructionIndex: Int? = nil

        var variableBeingRevoked: Variable? = nil



        // Find the index of the first 'revoke' method call.

        // We prioritize CallMethod as it's the most direct representation.

        for (i, instr) in program.code.enumerated() {

            if let call = instr.op as? CallMethod,

               call.methodName == "revoke",

               instr.numInputs > 0 // Ensure it's called on an object

            {

                revokeInstructionIndex = i

                variableBeingRevoked = instr.input(0) // Record the object whose revoke method is called

                break // Target the first CallMethod 'revoke' found

            }

        }



        // If no 'revoke' CallMethod was found, we cannot perform the targeted mutation.

        guard let revokeIdx = revokeInstructionIndex else {

            return nil

        }



        // Check if the variable being revoked is potentially a Proxy revocable pair.

        // This is a heuristic check. We look backwards for its definition.

        // A common pattern is: v_pair = Call(Proxy.revocable, ...); CallMethod 'revoke' on v_pair

        var isLikelyProxyRevocable = false

        if let targetVar = variableBeingRevoked {

            // Search backwards for the defining instruction

             for j in stride(from: revokeIdx - 1, through: 0, by: -1) {

                 let definingInstr = program.code[j]

                 if definingInstr.outputs.contains(targetVar) {

                     // Very basic check: Does the defining instruction involve 'Proxy' or 'revocable'?

                     // This is highly heuristic and depends on FuzzIL's IR generation.

                     // It might be a CallFunction, Construct, GetProperty sequence.

                     // We accept some ambiguity here to keep the mutator simpler.

                     // If the operation string contains "Proxy" or "revocable", consider it a match.

                     if definingInstr.op.name.contains("Proxy") || definingInstr.op.name.contains("revocable") {

                         isLikelyProxyRevocable = true

                         break

                     }

                      // Also check if inputs involve builtins like 'Proxy'

                     for inputVar in definingInstr.inputs {

                         if b.currentRoot.builtins.containsValue(inputVar) && b.currentRoot.builtins.first(where: { $0.value == inputVar })?.key == "Proxy" {

                             isLikelyProxyRevocable = true

                             break

                         }

                     }

                     if isLikelyProxyRevocable { break }



                     // If definition found, stop searching backwards for this variable.

                     break

                 }

             }

        }



        // If it doesn't seem related to Proxy.revocable based on our heuristic, maybe don't mutate.

        // However, for this specific request, the goal is to remove *the* revoke call causing issues.

        // So, we proceed even without strong confirmation, as removing any revoke might achieve the goal.

        // if !isLikelyProxyRevocable { return nil }





        // Build the new program, skipping the identified 'revoke' instruction.

        b.adopting(from: program) {

            for i in 0..<program.code.count {

                if i != revokeIdx {

                    // Keep the instruction

                    b.adopt(program.code[i])

                } else {

                    // Skip the instruction instead of adopting it.

                    // Add a comment for clarity in FuzzIL output.

                    b.appendComment("Instruction \(i) (CallMethod 'revoke' on \(variableBeingRevoked?.identifier ?? "unknown")) removed by RemoveRevokeCallMutator")

                    // Note: We assume the output of 'revoke()' (usually undefined) is not used later.

                    // If it were, simply removing the instruction could invalidate the program.

                    // Fuzzilli's sanitizer should catch such cases later if they occur.

                }

            }

        }



        // Finalize the program built without the revoke call.

        let mutatedProgram = b.finalize()



        // Basic check: ensure the program isn't empty after mutation.

        guard !mutatedProgram.isEmpty else {

             return nil

        }



        // Return the modified program.

        return mutatedProgram

    }

}
