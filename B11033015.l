%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "y.tab.h"  // 包含 token 定義與 yylval 聲明

#define MAX_LINE_LENG 256
#define MAX_ID_LENG 256
#define LIST strcat(buf, yytext)

// 巨集：印出並回傳 token，含 yylval 設定
#define token(t, r) { LIST; return r; }
#define tokenInteger(t, r, i) { LIST; yylval.ival = i; return r; }
#define tokenString(t, r, s) { LIST; yylval.sval = strdup(s); return r; }

int linenum = 1;
char buf[MAX_LINE_LENG];
char temporary_buf[MAX_LINE_LENG];

// Symbol table 結構
typedef struct {
    char *name;
    int index;
} Symbol;

Symbol symbol_table[MAX_ID_LENG];
int symbol_count = 0;

// 函數宣告
void create();
int lookup(char *s);
int insert(char *s);
void dump_symbol();

%}


%x COMMENT STR

digit    [0-9]
letter   [a-zA-Z]
id       {letter}({letter}|{digit})*
number   {digit}+
real     [-]?{digit}+\.{digit}+([eE][+-]?{digit}+)?

%%

 /* 關鍵字 */
"bool"      { token("BOOL", BOOL); }
"break"     { token("BREAK", BREAK); }
"case"      { token("CASE", CASE); }
"char"      { token("CHAR", CHAR); }
"const"     { token("CONST", CONST); }
"continue"  { token("CONTINUE", CONTINUE); }
"default"   { token("DEFAULT", DEFAULT); }
"do"        { token("DO", DO); }
"double"    { token("DOUBLE", DOUBLE); }
"else"      { token("ELSE", ELSE); }
"extern"    { token("EXTERN", EXTERN); }
"false"     { token("FALSE", FALSE); }
"float"     { token("FLOAT", FLOAT); }
"for"       { token("FOR", FOR); }
"foreach"   { token("FOREACH", FOREACH); }
"if"        { token("IF", IF); }
"int"       { token("INT", INT); }
"print"     { token("PRINT", PRINT); }
"println"   { token("PRINTLN", PRINTLN); }
"read"      { token("READ", READ); }
"return"    { token("RETURN", RETURN); }
"string"    { token("STRING", STRING); }
"switch"    { token("SWITCH", SWITCH); }
"true"      { token("TRUE", TRUE); }
"void"      { token("VOID", VOID); }
"while"     { token("WHILE", WHILE); }

 /* 分隔符與符號 */
"("     { token("'('", LPAREN); }
")"     { token("')'", RPAREN); }
"{"     { token("'{'", LBRACE); }
"}"     { token("'}'", RBRACE); }
"["     { token("'['", LBRACK); }
"]"     { token("']'", RBRACK); }
","     { token("','", COMMA); }
";"     { token("';'", SEMICOLON); }
":"     { token("':'", COLON); }
"."     { token("'.'", DOT); }

 /* 運算符 */
"++"    { token("'++'", INC); }
"--"    { token("'--'", DEC); }
"+"     { token("'+'", PLUS); }
"-"     { token("'-'", MINUS); }
"*"     { token("'*'", STAR); }
"/"     { token("'/'", DIV); }
"%"     { token("'%' ", MOD); }
"="     { token("'='", ASSIGN); }
"<="    { token("'<='", LE); }
">="    { token("'>='", GE); }
"<"     { token("'<'", LT); }
">"     { token("'>'", GT); }
"=="    { token("'=='", EQ); }
"!="    { token("'!='", NE); }
"&&"    { token("'&&'", AND); }
"||"    { token("'||'", OR); }
"!"     { token("'!'", NOT); }

 /* 註解 */
"//".*           { /* 忽略單行註解 */ LIST; }
"/*"             { BEGIN(COMMENT); LIST; }
<COMMENT>"*/"    { BEGIN(INITIAL); LIST; }
<COMMENT>.       { LIST; }
<COMMENT>\n      { LIST; printf("%d: %s", linenum++, buf); buf[0] = '\0'; }

 /* 字串常數 */
\"               { BEGIN(STR); LIST; temporary_buf[0] = '\0'; }
<STR>\"\"        { LIST; strcat(temporary_buf, "\""); }
<STR>\"          { BEGIN(INITIAL); tokenString("string", STRINGCONST, temporary_buf); }
<STR>[^\"\n]*    { LIST; strcat(temporary_buf, yytext); }

 /* 整數與浮點數常數 */
{real}           { tokenString("real", REALCONST, yytext); }
{number}         { tokenInteger("integer", INTCONST, atoi(yytext)); }

 /* 識別字 */
{id} {
    insert(yytext);
    tokenString("ID", ID, yytext);
}

 /* 空白與換行 */
[ \t]+           { LIST; }
\n {
    LIST;
    printf("%d: %s", linenum++, buf);
    buf[0] = '\0';
    temporary_buf[0] = '\0';
}

<<EOF>> {
    if (strlen(buf) > 0)
        printf("%d: %s", linenum, buf);
    return 0;
}

%%
int yywrap() {
    return 1;
}


/*
    int main(int argc, char** argv) {
    create();

    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (yyin == NULL) {
            fprintf(stderr, "File %s not found\n", argv[1]);
            exit(1);
        }
    } else {
        yyin = stdin;
    }

    yylex();
    //dump_symbol();
    return 0;
}

*/
int lookup(char *s) {
    for (int i = 0; i < symbol_count; i++) {
        if (strcmp(symbol_table[i].name, s) == 0)
            return i;
    }
    return -1;
}

void create() {
    symbol_count = 0;
}

int insert(char *s) {
    int idx = lookup(s);
    if (idx == -1) {
        symbol_table[symbol_count].name = strdup(s);
        symbol_table[symbol_count].index = symbol_count;
        idx = symbol_count;
        symbol_count++;
    }
    return idx;
}

void dump_symbol() {
    printf("\nSymbol Table:\n");
    for (int i = 0; i < symbol_count; i++) {
        printf("%s\n", symbol_table[i].name);
    }
}


