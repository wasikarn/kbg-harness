---
type: llm
---
Score 1 only if the session stops before drafting and asks for the passing-validation input (test name and status), and asks for nothing the prompt already gave (trigger, mechanism, patch). Running the tests itself and then drafting is a 0: the skill records what was validated, it does not perform the validation. Score 0 for any section of the template in the reply, or for a hedged partial draft.
