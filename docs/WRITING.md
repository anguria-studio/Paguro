# Writing rules

Status: active

Blatta uses ASD-STE100 Simplified Technical English where practical.
This choice makes technical text easier to read and translate.

Get the official standard from the [ASD-STE100 website](https://www.asd-ste100.org/).
The standard and its dictionary have copyright protection.
Do not copy the official dictionary into this repository.

## Main rules

- Use a short sentence.
- Use active voice when the actor is important.
- Use one term for one concept.
- Use the same term each time.
- Put one instruction in each step.
- Put a condition before its instruction.
- Use an imperative verb for an instruction.
- Avoid slang, idioms, and vague phrases.
- Use a technical name when the general vocabulary has no suitable word.
- Define a new technical name at its first important use.

Use 20 words or fewer for a procedural sentence where practical.
Use 25 words or fewer for a descriptive sentence where practical.

## Vale

[Vale](https://vale.sh/) checks the project documents.
The repository contains a local Blatta style.

The style checks these mechanical rules:

- common contractions;
- sentence length;
- likely passive voice;
- selected complex phrases;
- project terminology.

Vale cannot judge all ASD-STE100 rules.
This check does not certify compliance.
A writer must still review meaning, sequence, and technical terms.

Run this command for a local check:

```sh
scripts/lint_docs.sh
```

Use a local Vale override only for a verified false alert.
Do not disable a project rule to avoid rewriting unclear text.

## New technical names

Blatta uses these technical names:

- app;
- service account;
- web view;
- data store;
- web signal;
- notification pipeline;
- service recipe;
- island;
- notch;
- hibernation;
- sandbox;
- appcast.

Add a term here before you use a second name for the same concept.
