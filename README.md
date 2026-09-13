# NTUST SD Compiler

A compiler for a custom programming language, built with **Lex** and **Yacc** (C).  
Generates executable **Java Bytecode (Jasmin assembly)**.

## Features

- Lexical analysis, parsing, semantic analysis (symbol table, scope, type checking)
- Code generation to Java Bytecode (Jasmin)
- Supports `if`, `while`, `for`, `foreach`, functions, and `print`/`println`

## Build & Run

```bash
make                  # Build parser
./parser sample.sd    # → sample.jasm
