%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// 除錯用巨集
#define Trace(t) printf(">> %s\n", t)

// 型態常數定義
#define TYPE_INT    1
#define TYPE_FLOAT  2
#define TYPE_BOOL   3
#define TYPE_STRING 4
#define TYPE_VOID   5

// 參數節點結構，用於函數參數與呼叫
struct ParamNode;
typedef struct ParamNode {
    int type; // 參數型態
    char *name; // 參數名稱
    int is_array; // 是否為陣列
    int dim_count; // 維度數
    int *sizes; // 各維度大小
    struct ParamNode *next; // 下一個參數
} ParamNode;

// 符號表節點結構
typedef struct SymbolNode {
    char *name;         // 符號名稱
    int type;           // 符號類型 (TYPE_INT, TYPE_FLOAT, etc.)
    int is_const;       // 是否為常數
    int is_array;       // 是否為 array
    int *sizes;         // 各維度大小
    int dim_count;      // 維度數
    int local_var_num;
    union {
        int int_value;          // 整數值
        float float_value;      // 浮點數值
        char *string_value;     // 字符串值
        int bool_value;        // 是否為常數 1:是, 0:否
    } value;
    struct SymbolNode *next;  // 下一個符號
    
} SymbolNode;

// 作用域層級的結構
typedef struct ScopeNode {
    SymbolNode *symbols;       // 指向該作用域的符號串列
    struct ScopeNode *parent;  // 指向上一層作用域
    int next_local_var_num;
} ScopeNode;

// 函數表結構
typedef struct FunctionNode {
    char *name;   // 函數名稱
    int return_type;  // 回傳型態
    ParamNode *params;  // 參數串列
    struct FunctionNode *next;  // 下一個函數
} FunctionNode;

// 全域變數
FunctionNode *function_table = NULL;
ScopeNode *current_scope = NULL;
int scope_level = 0;    // 目前的作用域層級
int has_return = 0;

// 符號表與作用域相關函數宣告
void enter_scope();
void exit_scope();
SymbolNode* lookup_symbol(char *name);
SymbolNode* lookup_symbol_in_current_scope(char *name);
void insert_symbol(char *name, int type, int is_const);
void set_const_value(char *name, int type, void *value);
void dump_symbol_table();
void dump_function_table();
void insert_array_symbol(char *name, int type, int dim_count, int *sizes);
void insert_function(char *name, int return_type, ParamNode *params);
void free_param_list(ParamNode *p);
void free_all_scopes();
FunctionNode* lookup_function(char *name);
ParamNode* make_param(int type, char *name);
void generate_class_header();
void generate_class_footer();

// 其他全域變數
void yyerror(const char *msg);
int yylex();
int current_type = 0;
int assign_to_const = 0;
int label_counter = 0;
int g_if_false_label = 0;
int g_if_end_label = 0;
int g_while_begin_label = 0;
int g_while_exit_label = 0;
int g_for_begin_label = 0;
int g_for_exit_label = 0;
int g_for_update_label = 0;
int current_function_return_type = 0; 
int for_update_mode = 0;
int g_foreach_begin = 0;
int g_foreach_exit = 0;
SymbolNode *g_foreach_var = NULL;
char for_update_code[1024];
int no_emit_code = 0;
extern FILE *yyin;
FILE *output_file = NULL;
char class_name[256];
%}

// Yacc/Bison 的型態定義區
%union {
    int ival;
    char* sval;
    struct {
        int type;
        int is_const; // 1: 常數, 0: 變數或運算式含ID
        int is_array;     
        int dim_count;     
        int *sizes; 
        int is_id;
        char* id_name;
        int is_simple;
        union {
            int ival;
            char* sval;
            int bval;
        } val;
    } exprval;
    struct {
        int left_val;
        int right_val;
    } rangeval;
    struct ParamNode *param;
    struct {
        int dim_count;
        int *sizes;
    } arrayinfo;
}

//非終結符號型態宣告
%type <exprval> expression func_call
%type <rangeval> range_expr
%type <param> formal_params formal_param param_list expr_list_opt expr_list
%type <arrayinfo> array_dims array_index


// Tokens from lex 
%token <sval> ID STRINGCONST REALCONST
%token <ival> INTCONST

%token BOOL BREAK CASE CHAR CONST CONTINUE DEFAULT DO DOUBLE
%token ELSE EXTERN FALSE FLOAT FOR FOREACH IF INT PRINT PRINTLN
%token READ RETURN STRING SWITCH TRUE VOID WHILE

%token PLUS MINUS STAR DIV MOD INC DEC
%token ASSIGN
%token LT LE GT GE EQ NE
%token AND OR NOT

%token LPAREN RPAREN LBRACE RBRACE LBRACK RBRACK
%token COMMA SEMICOLON COLON DOT

// 運算子優先順序
%left OR
%left AND
%right NOT
%left EQ NE
%left LT LE GT GE
%left PLUS MINUS
%left STAR DIV MOD
%right UMINUS INC DEC
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%type <ival>  type

%start program

%%

// 主程式入口
program
    : decl_list
    {
        Trace("Reducing: program -> decl_list");
    }
    ;

// 宣告列表，可為空
decl_list
    : decl_list declaration
    | /* empty */
    ;

// 單一宣告（變數、常數、函數）
declaration
    : var_decl
    | const_decl
    | func_decl
    ;

// 變數宣告 
var_decl
    : type var_list SEMICOLON
    {
        current_type = $1;
        Trace("Reducing: var_decl -> type var_list ';'");
    }
    ;

// 變數列表，可為單一變數或陣列 
var_list
    : var_list COMMA var_item
    {
        Trace("Reducing: var_list -> var_list ',' var_item");
    }
    | var_item
    {
        Trace("Reducing: var_list -> var_item");
    }
    | array_item
    {
        Trace("Reducing: var_list -> array_item");
    }
    ;

// 陣列宣告項目 
array_item
    : ID array_dims
    {
        yyerror("This compiler does not support array declarations.");
        return 1;
        insert_array_symbol($1, current_type, $2.dim_count, $2.sizes);
        Trace("Reducing: array_item -> ID array_dims");
    }
    ;

// 陣列維度描述 
array_dims
    : array_dims LBRACK INTCONST RBRACK
    {
        $$.dim_count = $1.dim_count + 1;
        $$.sizes = realloc($1.sizes, sizeof(int) * $$.dim_count);
        $$.sizes[$1.dim_count] = $3;
    }
    | LBRACK INTCONST RBRACK
    {
        $$.dim_count = 1;
        $$.sizes = malloc(sizeof(int));
        $$.sizes[0] = $2;
    }
    ;

// 單一變數宣告（可初始化） 
var_item
    : ID
    {
        insert_symbol($1, current_type, 0);  // 插入符號，非常數
        if (scope_level == 1 && output_file) 
        {
            // 根據類型生成欄位宣告
            switch (current_type) 
            {
                case TYPE_INT:
                    fprintf(output_file, "    field static int %s\n", $1);
                    break;
            }
        }
        Trace("Reducing: var_item -> ID");
    }
    | ID ASSIGN expression
    {
        if (current_type != $3.type) {
            char error_msg[100];
            sprintf(error_msg, "Type mismatch in assignment: expected type %d, got type %d", 
                    current_type, $3.type);
            yyerror(error_msg);
            return 1;
        }
        insert_symbol($1, current_type, 0);  // 插入符號，非常數

        if (scope_level == 1 && output_file && $3.is_const) {
            // 全域變數初始化
            switch (current_type) {
                case TYPE_INT:
                    fprintf(output_file, "    field static int %s = %d\n", $1, $3.val.ival);
                    break;
                // 你可以擴充 BOOL/STRING 型態
            }
        }

        if (scope_level > 1 && output_file && current_type != TYPE_STRING && current_type != TYPE_FLOAT) {
            SymbolNode *sym = lookup_symbol_in_current_scope($1);

            // 只有在簡單表達式時才生成載入 bytecode
            if ($3.is_simple) {
                // 處理 assignment 右值為 const id/int/bool/string
                if ($3.is_const) {
                    SymbolNode *rhs = NULL;
                    if ($3.is_id) {
                        rhs = lookup_symbol($3.id_name);
                    }
                    int type = rhs ? rhs->type : current_type;
                    if (type == TYPE_INT) {
                        int val = rhs ? rhs->value.int_value : $3.val.ival;
                        fprintf(output_file, "        sipush %d\n", val);
                    } else if (type == TYPE_BOOL) {
                        int val = rhs ? rhs->value.bool_value : $3.val.bval;
                        fprintf(output_file, "        iconst_%d\n", val ? 1 : 0);
                    }
                } else if ($3.is_id && !$3.is_const) {
                    // 右值是變數（非 const）
                    SymbolNode *rhs = lookup_symbol($3.id_name);
                    if (rhs) {
                        if (rhs->local_var_num >= 0) {
                            fprintf(output_file, "        iload %d\n", rhs->local_var_num);
                        } else {
                            fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
            }
            // 複雜表達式的 bytecode 已在 expression 規則中生成
            
            // 不管是簡單還是複雜表達式都要存儲結果
            fprintf(output_file, "        istore %d\n", sym->local_var_num);
        }
        Trace("Reducing: var_item -> ID '=' expression");
    }
    ;

if_stmt
    : IF LPAREN expression RPAREN
      {
          if ($3.type != TYPE_BOOL) {
              yyerror("Condition expression must be boolean type");
              return 1;
          }
          
          g_if_false_label = label_counter++;  // 創建條件為假時要跳到的標籤
          
          if (output_file && scope_level > 1 && $3.is_const && !$3.is_id) {
              fprintf(output_file, "        iconst_%d\n", $3.val.bval ? 1 : 0);
          }
          
          if (output_file && scope_level > 1) {
              fprintf(output_file, "        ifeq L%d\n", g_if_false_label);
          }
      }
      statement
      {
          g_if_end_label = label_counter++;  // 創建 if 結束後的標籤
      }
      if_else_part
    ;

if_else_part
    : ELSE
      {
          if (output_file && scope_level > 1) {
              fprintf(output_file, "        goto L%d\n", g_if_end_label);  // 跳過 else 部分
              fprintf(output_file, "L%d:\n", g_if_false_label);  // false 標籤（開始 else 部分）
          }
      }
      statement
      {
          if (output_file && scope_level > 1) {
              fprintf(output_file, "L%d:\n", g_if_end_label);  // 整個 if-else 結束
          }
          Trace("Reducing: if_stmt -> if '(' expression ')' statement else statement");
      }
    | %prec LOWER_THAN_ELSE  /* 空規則，表示沒有 else */
      {
          if (output_file && scope_level > 1) {
              fprintf(output_file, "L%d:\n", g_if_false_label);  // 只有 if 的結束點
          }
          Trace("Reducing: if_stmt -> if '(' expression ')' statement");
      }
    ;

// while 迴圈 
while_stmt
    : WHILE 
      {
          // 在條件檢查前插入開始標籤
          g_while_begin_label = label_counter++;
          
          if (output_file && scope_level > 1) {
              fprintf(output_file, "Lbegin%d:\n", g_while_begin_label);
          }
      }
      LPAREN expression RPAREN
      {
          // 檢查條件是否為布林類型
          if ($4.type != TYPE_BOOL) {
              yyerror("Condition expression in while statement must be of type bool");
              return 1;
          }
          
          // 為條件跳轉創建標籤
          g_while_exit_label = label_counter++;
          
          // 生成條件判斷代碼
          if (output_file && scope_level > 1) {
              // 如果運算元是簡單的，需要顯式載入
              if ($4.is_simple) {
                  if ($4.is_const && !$4.is_id) {
                      fprintf(output_file, "        iconst_%d\n", $4.val.bval ? 1 : 0);
                  } else if ($4.is_id) {
                      SymbolNode *sym = lookup_symbol($4.id_name);
                      if (sym && sym->is_const) {
                          fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                      } else if (sym) {
                          if (sym->local_var_num >= 0)
                              fprintf(output_file, "        iload %d\n", sym->local_var_num);
                          else
                              fprintf(output_file, "        getstatic int %s.%s\n", class_name, $4.id_name);
                      }
                  }
              }
              // 複雜運算元的結果已在堆疊頂端
              
              // 生成退出迴圈的條件跳轉指令
              fprintf(output_file, "        ifeq Lexit%d\n", g_while_exit_label);
          }
      }
      statement
      {
          if (output_file && scope_level > 1) {
              // 迴圈體執行完後，跳回條件判斷處
              fprintf(output_file, "        goto Lbegin%d\n", g_while_begin_label);
              
              // 標記退出迴圈的標籤
              fprintf(output_file, "Lexit%d:\n", g_while_exit_label);
          }
          
          Trace("Reducing: while_stmt -> while '(' expression ')' statement");
      }
    ;

// for 迴圈 
for_stmt
    : FOR LPAREN for_init_stmt
      {
          g_for_begin_label = label_counter++;
          g_for_exit_label = label_counter++;
          g_for_update_label = label_counter++;
          for_update_code[0] = '\0';
          for_update_mode = 1;
          if (output_file && scope_level > 1) {
              fprintf(output_file, "Lfor_begin%d:\n", g_for_begin_label);
          }
      }
      expression SEMICOLON
      {
          if ($5.type != TYPE_BOOL) {  
              yyerror("Condition expression in for statement must be of type bool");
              return 1;
          }

          if (output_file && scope_level > 1) {
             
              if ($5.is_simple) { 
                  if ($5.is_const && !$5.is_id) {  
                      fprintf(output_file, "        iconst_%d\n", $5.val.bval ? 1 : 0);
                  } else if ($5.is_id) {  
                      SymbolNode *sym = lookup_symbol($5.id_name);  
                      if (sym && sym->is_const) {
                          fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                      } else if (sym) {
                          if (sym->local_var_num >= 0)
                              fprintf(output_file, "        iload %d\n", sym->local_var_num);
                          else
                              fprintf(output_file, "        getstatic int %s.%s\n", class_name, $5.id_name);  // 修复：将 $4 替换为 $5
                      }
                  }
              }
              
              fprintf(output_file, "        ifeq Lfor_exit%d\n", g_for_exit_label);
          }
      }
      for_update_expr
      {
        for_update_mode = 0;
      }
      RPAREN statement
      {
          if (output_file && scope_level > 1) {
              
              fputs(for_update_code, output_file);
              fprintf(output_file, "Lfor_update%d:\n", g_for_update_label);
              fprintf(output_file, "        goto Lfor_begin%d\n", g_for_begin_label);
              fprintf(output_file, "Lfor_exit%d:\n", g_for_exit_label);
          }
          
          for_update_code[0] = '\0';
          Trace("Reducing: for_stmt -> for '(' for_init_stmt expression ';' for_update_expr ')' statement");
      }
    ;

// for 迴圈初始化 
for_init_stmt
    : var_decl
    {
        Trace("Reducing: for_init_stmt -> var_decl");
    }
    | assign_stmt
    {
        Trace("Reducing: for_init_stmt -> assign_stmt");
    }
    | expression SEMICOLON
    {
        Trace("Reducing: for_init_stmt -> expression ';'");
    }
    | SEMICOLON
    {
        Trace("Reducing: for_init_stmt -> ';'");
    }
    ;

// for 迴圈更新表達式
for_update_expr
    : assign_expr
    {
        Trace("Reducing: for_update_expr -> expression");
    }
    | inc_dec_expr
    {
        Trace("Reducing: for_update_expr -> inc_dec_expr");
    }
    | /* empty */
    {
        Trace("Reducing: for_update_expr -> (empty)");
    }
    ;

// foreach 迴圈 
foreach_stmt
    : FOREACH LPAREN ID COLON range_expr RPAREN
      {
        // 前置區塊：i = min(a, b); while (i <= max(a, b))
        SymbolNode *sym = lookup_symbol($3);
        if (!sym) {
            insert_symbol($3, TYPE_INT, 0);
            sym = lookup_symbol($3);
        }
        int min_val = ($5.left_val < $5.right_val) ? $5.left_val : $5.right_val;
        int max_val = ($5.left_val > $5.right_val) ? $5.left_val : $5.right_val;

        int foreach_begin = label_counter++;
        int foreach_exit = label_counter++;

        if (output_file && scope_level > 1) {
            // i = min(a, b)
            fprintf(output_file, "        sipush %d\n", min_val);
            if (sym->local_var_num >= 0)
                fprintf(output_file, "        istore %d\n", sym->local_var_num);
            else
                fprintf(output_file, "        putstatic int %s.%s\n", class_name, $3);

            // while 標籤
            fprintf(output_file, "Lforeach_begin%d:\n", foreach_begin);

            // i <= max(a, b)
            if (sym->local_var_num >= 0)
                fprintf(output_file, "        iload %d\n", sym->local_var_num);
            else
                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3);

            fprintf(output_file, "        sipush %d\n", max_val);
            fprintf(output_file, "        isub\n");
            fprintf(output_file, "        ifgt Lforeach_exit%d\n", foreach_exit);
        }

        // 存到全域變數，讓 statement 區塊能用
        g_foreach_begin = foreach_begin;
        g_foreach_exit = foreach_exit;
        g_foreach_var = sym;
      }
      statement
      {
        // 這裡產生 i = i + 1; 以及 while 結尾
        SymbolNode *sym = g_foreach_var;
        int foreach_begin = g_foreach_begin;
        int foreach_exit = g_foreach_exit;

        if (output_file && scope_level > 1) {
            // i = i + 1
            if (sym->local_var_num >= 0)
                fprintf(output_file, "        iinc %d 1\n", sym->local_var_num);
            else {
                fprintf(output_file, "        getstatic int %s.%s\n", class_name, sym->name);
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "        iadd\n");
                fprintf(output_file, "        putstatic int %s.%s\n", class_name, sym->name);
            }
            // goto while begin
            fprintf(output_file, "        goto Lforeach_begin%d\n", foreach_begin);
            // while exit 標籤
            fprintf(output_file, "Lforeach_exit%d:\n", foreach_exit);
        }
        Trace("Reducing: foreach_stmt -> foreach '(' ID ':' range_expr ')' statement");
      }

// 範圍運算式 
range_expr
    : expression DOT DOT expression
    {
        int left_val = 0, right_val = 0;
        if ($1.is_const && !$1.is_id)
            left_val = $1.val.ival;
        else if ($1.is_id) {
            SymbolNode *sym = lookup_symbol($1.id_name);
            if (sym && sym->is_const)
                left_val = sym->value.int_value;
        }
        if ($4.is_const && !$4.is_id)
            right_val = $4.val.ival;
        else if ($4.is_id) {
            SymbolNode *sym = lookup_symbol($4.id_name);
            if (sym && sym->is_const)
                right_val = sym->value.int_value;
        }
        $$.left_val = left_val;
        $$.right_val = right_val;
        Trace("Reducing: range_expr -> expression '..' expression");
    }
    ;

// 常數宣告 
const_decl
    : CONST { assign_to_const = 1;} type ID ASSIGN expression SEMICOLON
    {
        
        Trace(assign_to_const == 1 ? "assign_to_const == 1" : "assign_to_const == 0");

        if ($3 != $6.type) {
            char error_msg[100];
            sprintf(error_msg, "Type mismatch in constant declaration: expected type %d, got type %d", 
                    $3, $6.type);
            yyerror(error_msg);
            assign_to_const = 0;  // 重設為 0
            return 1;
        }
        
        insert_symbol($4, $3, 1);  // 插入符號，是常數
        
        // 設定常數值
        if ($6.is_const && $3 == $6.type) {
            if ($3 == TYPE_INT) {
                set_const_value($4, TYPE_INT, &($6.val.ival));
            } else if ($3 == TYPE_FLOAT) {
                float f = atof($6.val.sval);
                set_const_value($4, TYPE_FLOAT, &f);
            } else if ($3 == TYPE_STRING) {
                set_const_value($4, TYPE_STRING, $6.val.sval);
            } else if ($3 == TYPE_BOOL) {
                set_const_value($4, TYPE_BOOL, &($6.val.bval));
            }
            
        }
        Trace("Reducing: const_decl -> const type ID = expression ';'");
        assign_to_const = 0;
        Trace(assign_to_const == 1 ? "assign_to_const == 1" : "assign_to_const == 0");
        
    }
    ;

// 函數宣告 
func_decl
    : type ID LPAREN formal_params RPAREN
      {
          current_function_return_type = $1;
          has_return = 0;
          insert_function($2, $1, $4);
          enter_scope();

          // 參數依序插入符號表，並給 local_var_num
          ParamNode *p = $4;
          int param_idx = 0;
          while (p) {
              if (p->is_array) {
                  insert_array_symbol(p->name, p->type, p->dim_count, p->sizes);
              } else {
                  insert_symbol(p->name, p->type, 0);
              }
              SymbolNode *sym = lookup_symbol_in_current_scope(p->name);
              if (sym) sym->local_var_num = param_idx++;
              p = p->next;
          }

          // 產生 method header
          if ($1 == TYPE_VOID && strcmp($2, "main") == 0) {
              fprintf(output_file, "    method public static void main(java.lang.String[])\n");
              fprintf(output_file, "    max_stack 15\n");
              fprintf(output_file, "    max_locals 15\n");
              fprintf(output_file, "    {\n");
          } else {
              // 產生參數型態字串
              char param_types[128] = "";
              ParamNode *p = $4;
              while (p) {
                  if (strlen(param_types) > 0) strcat(param_types, ", ");
                  switch (p->type) {
                      case TYPE_INT: strcat(param_types, "int"); break;
                      case TYPE_FLOAT: strcat(param_types, "float"); break;
                      case TYPE_BOOL: strcat(param_types, "boolean"); break;
                      case TYPE_STRING: strcat(param_types, "java.lang.String"); break;
                  }
                  p = p->next;
              }
              char *ret_type = "";
              switch ($1) {
                  case TYPE_INT: ret_type = "int"; break;
                  case TYPE_FLOAT: ret_type = "float"; break;
                  case TYPE_BOOL: ret_type = "boolean"; break;
                  case TYPE_STRING: ret_type = "java.lang.String"; break;
                  case TYPE_VOID: ret_type = "void"; break;
              }
              fprintf(output_file, "    method public static %s %s(%s)\n", ret_type, $2, param_types);
              fprintf(output_file, "    max_stack 15\n");
              fprintf(output_file, "    max_locals 15\n");
              fprintf(output_file, "    {\n");
          }
      }
      block
      {
          if (current_function_return_type != TYPE_VOID && has_return == 0) {
              char error_msg[100];
              sprintf(error_msg, "Function '%s' missing return statement", $2);
              yyerror(error_msg);
              return 1;
          }
          if (current_function_return_type == TYPE_VOID && has_return == 0) {
              fprintf(output_file, "        return\n");
          }

          // Close function
          fprintf(output_file, "    }\n");
          
          // If this was the main function, close the class
          if (current_function_return_type == TYPE_VOID && strcmp($2, "main") == 0) {
              generate_class_footer();
          }

          Trace("Reducing: func_decl -> type ID '(' formal_params ')' block");
          current_function_return_type = 0;
          exit_scope();
      }
    ;

// 參數列表 
formal_params
    : param_list { $$ = $1; }
    | /* empty */ { $$ = NULL; }
    ;

// 參數串列 
param_list
    : param_list COMMA formal_param
      { 
        ParamNode *tail = $1;
        while (tail->next) tail = tail->next;
        tail->next = $3;
        $$ = $1;
      }
    | formal_param { $$ = $1; }
    ;

// 單一參數 
formal_param
    : type ID { $$ = make_param($1, $2); }
    | type ID array_dims
      {
        // 檢查 array_dims 是否每一維都指定了大小
        for (int i = 0; i < $3.dim_count; ++i) {
            if ($3.sizes[i] <= 0) {
                char error_msg[100];
                sprintf(error_msg, "Array parameter '%s' must have all dimensions fully declared", $2);
                yyerror(error_msg);
                exit(1);
            }
        }
        // 你可以在 ParamNode 結構裡加 is_array, dim_count, sizes 等欄位
        ParamNode *p = make_param($1, $2);
        p->is_array = 1;
        p->dim_count = $3.dim_count;
        p->sizes = malloc(sizeof(int) * $3.dim_count);
        for (int i = 0; i < $3.dim_count; ++i)
            p->sizes[i] = $3.sizes[i];
        $$ = p;
      }
    ;

// 型態宣告 
type
    : INT
    { 
        current_type = TYPE_INT;
        $$ = TYPE_INT;
        Trace("Reducing: type -> INT");
    }
    | FLOAT
    { 
        current_type = TYPE_FLOAT;
        $$ = TYPE_FLOAT;
        Trace("Reducing: type -> FLOAT");
    }
    | BOOL
    { 
        current_type = TYPE_BOOL;
        $$ = TYPE_BOOL;
        Trace("Reducing: type -> BOOL");
    }
    | STRING
    { 
        current_type = TYPE_STRING;
        $$ = TYPE_STRING;
        Trace("Reducing: type -> STRING");
    }
    | VOID
    { 
        current_type = TYPE_VOID;
        $$ = TYPE_VOID;
        Trace("Reducing: type -> VOID");
    }
    ;

// 區塊（大括號） 
block
    : LBRACE 
    {
        enter_scope();  // 進入新的作用域
    }
    stmt_list RBRACE
    {
        Trace("Reducing: block -> '{' stmt_list '}'");
        exit_scope();   // 離開當前作用域
    }
    ;

// 敘述串列 
stmt_list
    : stmt_list statement
    | /* empty */
    ;

// 單一敘述 
statement
    : var_decl
    | const_decl
    | assign_stmt
    | array_assign_stmt
    | return_stmt
    | print_stmt
    | println_stmt
    | read_stmt
    | inc_dec_stmt
    | empty_stmt
    | block
    | if_stmt
    | while_stmt
    | for_stmt
    | foreach_stmt
    | func_call_stmt
    ;


func_call_stmt
    : ID LPAREN expr_list_opt RPAREN SEMICOLON
    {
        // 檢查函數是否存在
        FunctionNode *fn = lookup_function($1);
        if (!fn) {
            char error_msg[100];
            sprintf(error_msg, "Function '%s' not defined", $1);
            yyerror(error_msg);
            return 1;
        }
        // 檢查必須是 void 函數
        if (fn->return_type != TYPE_VOID) {
            char error_msg[100];
            sprintf(error_msg, "Function '%s' is not void, cannot be called as a statement", $1);
            yyerror(error_msg);
            return 1;
        }
        // 檢查參數型態與數量（可複製 func_call 的檢查）
        ParamNode *formal = fn->params;
        ParamNode *actual = $3;
        int idx = 1;
        while (formal && actual) {
            if (formal->is_array) {
                if (!actual->is_array) {
                    char error_msg[100];
                    sprintf(error_msg, "Function '%s' argument %d: expected array", $1, idx);
                    yyerror(error_msg);
                    return 1;
                }
                if (formal->type != actual->type) {
                    char error_msg[100];
                    sprintf(error_msg, "Function '%s' argument %d: array type mismatch (expected %d, got %d)", $1, idx, formal->type, actual->type);
                    yyerror(error_msg);
                    return 1;
                }
                if (formal->dim_count != actual->dim_count) {
                    char error_msg[100];
                    sprintf(error_msg, "Function '%s' argument %d: array dimension mismatch (expected %d, got %d)", $1, idx, formal->dim_count, actual->dim_count);
                    yyerror(error_msg);
                    return 1;
                }
                for (int i = 0; i < formal->dim_count; ++i) {
                    if (formal->sizes[i] != actual->sizes[i]) {
                        char error_msg[100];
                        sprintf(error_msg, "Function '%s' argument %d: array size mismatch at dimension %d (expected %d, got %d)", $1, idx, i+1, formal->sizes[i], actual->sizes[i]);
                        yyerror(error_msg);
                        return 1;
                    }
                }
            } else {
                if (formal->type != actual->type) {
                    char error_msg[100];
                    sprintf(error_msg, "Function '%s' argument %d type mismatch: expected %d, got %d", $1, idx, formal->type, actual->type);
                    yyerror(error_msg);
                    return 1;
                }
            }
            formal = formal->next;
            actual = actual->next;
            idx++;
        }
        if (formal || actual) {
            char error_msg[100];
            sprintf(error_msg, "Function '%s' argument count mismatch", $1);
            yyerror(error_msg);
            return 1;
        }

        // 產生 invokestatic void ... bytecode
        if (output_file && scope_level > 1) {
            char param_types[128] = "";
            ParamNode *p = fn->params;
            while (p) {
                if (strlen(param_types) > 0) strcat(param_types, ", ");
                switch (p->type) {
                    case TYPE_INT: strcat(param_types, "int"); break;
                    case TYPE_FLOAT: strcat(param_types, "float"); break;
                    case TYPE_BOOL: strcat(param_types, "boolean"); break;
                    case TYPE_STRING: strcat(param_types, "java.lang.String"); break;
                }
                p = p->next;
            }
            fprintf(output_file, "        invokestatic void %s.%s(%s)\n", class_name, $1, param_types);
        }
        free_param_list($3);
        Trace("Reducing: func_call_stmt -> ID '(' expr_list_opt ')' ';'");
    }
    ;
// print 敘述 
print_stmt
    : PRINT { if (output_file) fprintf(output_file, "        getstatic java.io.PrintStream java.lang.System.out\n"); } expression SEMICOLON
    {
        if (output_file) {
            if ($3.type == TYPE_STRING && $3.is_const) {
                const char *val = $3.val.sval;
                if ($3.is_id) {
                    SymbolNode *sym = lookup_symbol($3.id_name);
                    if (sym && sym->is_const && sym->type == TYPE_STRING && sym->value.string_value)
                        val = sym->value.string_value;
                }
                fprintf(output_file, "        ldc \"%s\"\n", val);
                fprintf(output_file, "        invokevirtual void java.io.PrintStream.print(java.lang.String)\n");
            } else if ($3.type == TYPE_INT) {
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const)
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        else if (sym && sym->local_var_num >= 0)
                            fprintf(output_file, "        iload %d\n", sym->local_var_num);
                        else if (sym)
                            fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                    }
                }
                // 複雜運算式已經在 stack top，不需再載入
                fprintf(output_file, "        invokevirtual void java.io.PrintStream.print(int)\n");
            } else if ($3.type == TYPE_BOOL) {
                if ($3.is_simple) {
                    int val = 0;
                    if ($3.is_const && !$3.is_id) {
                        val = $3.val.bval ? 1 : 0;
                        fprintf(output_file, "        iconst_%d\n", val);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const)
                            fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                        else if (sym && sym->local_var_num >= 0)
                            fprintf(output_file, "        iload %d\n", sym->local_var_num);
                        else if (sym)
                            fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                    }
                }
                fprintf(output_file, "        invokevirtual void java.io.PrintStream.print(int)\n");
            } else {
                yyerror("PRINT only supports string constants/literals, int, or bool variables/constants.");
                return 1;
            }
        }
        Trace("Reducing: print_stmt -> print expression ';'");
    }

println_stmt
    : PRINTLN { if (output_file) fprintf(output_file, "        getstatic java.io.PrintStream java.lang.System.out\n"); } expression SEMICOLON
    {
        if (output_file) {
            if ($3.type == TYPE_STRING && $3.is_const) {
                const char *val = $3.val.sval;
                if ($3.is_id) {
                    SymbolNode *sym = lookup_symbol($3.id_name);
                    if (sym && sym->is_const && sym->type == TYPE_STRING && sym->value.string_value)
                        val = sym->value.string_value;
                }
                fprintf(output_file, "        ldc \"%s\"\n", val);
                fprintf(output_file, "        invokevirtual void java.io.PrintStream.println(java.lang.String)\n");
            } else if ($3.type == TYPE_INT) {
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const)
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        else if (sym && sym->local_var_num >= 0)
                            fprintf(output_file, "        iload %d\n", sym->local_var_num);
                        else if (sym)
                            fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                    }
                }
                // 複雜運算式已經在 stack top，不需再載入
                fprintf(output_file, "        invokevirtual void java.io.PrintStream.println(int)\n");
            } else if ($3.type == TYPE_BOOL) {
                if ($3.is_simple) {
                    int val = 0;
                    if ($3.is_const && !$3.is_id) {
                        val = $3.val.bval ? 1 : 0;
                        fprintf(output_file, "        iconst_%d\n", val);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const)
                            fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                        else if (sym && sym->local_var_num >= 0)
                            fprintf(output_file, "        iload %d\n", sym->local_var_num);
                        else if (sym)
                            fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                    }
                }
                fprintf(output_file, "        invokevirtual void java.io.PrintStream.println(int)\n");
            } else {
                yyerror("PRINTLN only supports string constants/literals, int, or bool variables/constants.");
                return 1;
            }
        }
        Trace("Reducing: println_stmt -> println expression ';'");
    }
    ;

// read 敘述 
read_stmt
    : READ ID SEMICOLON
    {
        yyerror("This compiler does not support READ statements.");
        return 1;
        SymbolNode *symbol = lookup_symbol($2);
        if (!symbol) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot read into const symbol: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Cannot read into array variable directly: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        Trace("Reducing: read_stmt -> read ID ';'");
    }
    | READ ID array_index SEMICOLON
    {
        yyerror("This compiler does not support READ statements.");
        return 1;
        SymbolNode *symbol = lookup_symbol($2);
        if (!symbol) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        if (!symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Variable is not an array: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        if ($3.dim_count != symbol->dim_count) {
            char error_msg[100];
            sprintf(error_msg, "Array index dimension mismatch for %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        for (int i = 0; i < $3.dim_count; ++i) {
            if ($3.sizes[i] < 0 || $3.sizes[i] >= symbol->sizes[i]) {
                char error_msg[100];
                sprintf(error_msg, "Array index out of bounds for %s", $2);
                yyerror(error_msg);
                free($3.sizes);
                return 1;
            }
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot read into const array element: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        Trace("Reducing: read_stmt -> read ID array_index ';'");
        free($3.sizes);
    }
    ;

// ++ -- 敘述 
inc_dec_expr
    : ID INC 
    {
        SymbolNode *symbol = lookup_symbol($1);
        if (symbol == NULL) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $1);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Cannot increment array variable directly: %s", $1);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot increment const symbol: %s", $1);
            yyerror(error_msg);
            return 1;
        }

        // 生成 bytecode，根據 for_update_mode 決定輸出或暫存
        if (output_file && scope_level > 1) {
            if (symbol->local_var_num >= 0) {
                if (for_update_mode) {
                    // 暫存到 buffer
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        iinc %d 1\n", symbol->local_var_num);
                } else {
                    // 直接輸出
                    fprintf(output_file, "        iinc %d 1\n", symbol->local_var_num);
                }
            } else {
                // 全域變數需要先載入、遞增、再存回
                if (for_update_mode) {
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        getstatic int %s.%s\n        iconst_1\n        iadd\n        putstatic int %s.%s\n",
                             class_name, $1, class_name, $1);
                } else {
                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1);
                    fprintf(output_file, "        iconst_1\n");
                    fprintf(output_file, "        iadd\n");
                    fprintf(output_file, "        putstatic int %s.%s\n", class_name, $1);
                }
            }
        }

        Trace("Reducing: inc_dec_stmt -> ID++ ';'");
    }
    | ID DEC 
    {
        SymbolNode *symbol = lookup_symbol($1);
        if (symbol == NULL) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $1);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Cannot decrement array variable directly: %s", $1);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot decrement const symbol: %s", $1);
            yyerror(error_msg);
            return 1;
        }

        // 生成 bytecode，根據 for_update_mode 決定輸出或暫存
        if (output_file && scope_level > 1) {
            if (symbol->local_var_num >= 0) {
                if (for_update_mode) {
                    // 暫存到 buffer
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        iinc %d -1\n", symbol->local_var_num);
                } else {
                    // 直接輸出
                    fprintf(output_file, "        iinc %d -1\n", symbol->local_var_num);
                }
            } else {
                // 全域變數需要先載入、遞減、再存回
                if (for_update_mode) {
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        getstatic int %s.%s\n        iconst_1\n        isub\n        putstatic int %s.%s\n",
                             class_name, $1, class_name, $1);
                } else {
                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1);
                    fprintf(output_file, "        iconst_1\n");
                    fprintf(output_file, "        isub\n");
                    fprintf(output_file, "        putstatic int %s.%s\n", class_name, $1);
                }
            }
        }

        Trace("Reducing: inc_dec_stmt -> ID-- ';'");
    }
    | INC ID 
    {
        SymbolNode *symbol = lookup_symbol($2);
        if (symbol == NULL) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Cannot increment array variable directly: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot increment const symbol: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        Trace("Reducing: inc_dec_stmt -> ++ID ';'");
    }
    | DEC ID 
    {
        SymbolNode *symbol = lookup_symbol($2);
        if (symbol == NULL) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Cannot decrement array variable directly: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot decrement const symbol: %s", $2);
            yyerror(error_msg);
            return 1;
        }
        Trace("Reducing: inc_dec_stmt -> --ID ';'");
    }
    | ID array_index INC 
    {
        SymbolNode *symbol = lookup_symbol($1);
        if (!symbol) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        if (!symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Variable is not an array: %s", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        if ($2.dim_count != symbol->dim_count) {
            char error_msg[100];
            sprintf(error_msg, "Array index dimension mismatch for %s", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        for (int i = 0; i < $2.dim_count; ++i) {
            if ($2.sizes[i] < 0 || $2.sizes[i] >= symbol->sizes[i]) {
                char error_msg[100];
                sprintf(error_msg, "Array index out of bounds for %s", $1);
                yyerror(error_msg);
                free($2.sizes);
                return 1;
            }
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot increment const array element: %s", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        Trace("Reducing: inc_dec_stmt -> ID array_index ++ ';'");
        free($2.sizes);
    }
    | ID array_index DEC 
    {
        SymbolNode *symbol = lookup_symbol($1);
        if (!symbol) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        if (!symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Variable is not an array: %s", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        if ($2.dim_count != symbol->dim_count) {
            char error_msg[100];
            sprintf(error_msg, "Array index dimension mismatch for %s", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        for (int i = 0; i < $2.dim_count; ++i) {
            if ($2.sizes[i] < 0 || $2.sizes[i] >= symbol->sizes[i]) {
                char error_msg[100];
                sprintf(error_msg, "Array index out of bounds for %s", $1);
                yyerror(error_msg);
                free($2.sizes);
                return 1;
            }
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot decrement const array element: %s", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        Trace("Reducing: inc_dec_stmt -> ID array_index -- ';'");
        free($2.sizes);
    }
    | INC ID array_index 
    {
        SymbolNode *symbol = lookup_symbol($2);
        if (!symbol) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        if (!symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Variable is not an array: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        if ($3.dim_count != symbol->dim_count) {
            char error_msg[100];
            sprintf(error_msg, "Array index dimension mismatch for %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        for (int i = 0; i < $3.dim_count; ++i) {
            if ($3.sizes[i] < 0 || $3.sizes[i] >= symbol->sizes[i]) {
                char error_msg[100];
                sprintf(error_msg, "Array index out of bounds for %s", $2);
                yyerror(error_msg);
                free($3.sizes);
                return 1;
            }
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot increment const array element: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        Trace("Reducing: inc_dec_stmt -> ++ID array_index ';'");
        free($3.sizes);
    }
    | DEC ID array_index 
    {
        SymbolNode *symbol = lookup_symbol($2);
        if (!symbol) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        if (!symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Variable is not an array: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        if ($3.dim_count != symbol->dim_count) {
            char error_msg[100];
            sprintf(error_msg, "Array index dimension mismatch for %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        for (int i = 0; i < $3.dim_count; ++i) {
            if ($3.sizes[i] < 0 || $3.sizes[i] >= symbol->sizes[i]) {
                char error_msg[100];
                sprintf(error_msg, "Array index out of bounds for %s", $2);
                yyerror(error_msg);
                free($3.sizes);
                return 1;
            }
        }
        if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot decrement const array element: %s", $2);
            yyerror(error_msg);
            free($3.sizes);
            return 1;
        }
        Trace("Reducing: inc_dec_stmt -> --ID array_index ';'");
        free($3.sizes);
    }
    ;

// ++/-- 敘述必須以分號結尾
inc_dec_stmt
    : inc_dec_expr SEMICOLON
    ;

// 空敘述（單一分號）
empty_stmt
    : SEMICOLON
    {
        Trace("Reducing: empty_stmt -> ';'");
    }
    ;

// return 敘述，檢查型態是否正確
return_stmt
    : RETURN expression SEMICOLON
    {
        has_return = 1;
        if ($2.type != current_function_return_type) {
            char error_msg[100];
            sprintf(error_msg, "Return type mismatch: function expects type %d, got type %d", 
                    current_function_return_type, $2.type);
            yyerror(error_msg);
            return 1;
        }

        if (output_file) {
            // 先將 return 值壓入 stack
            if (current_function_return_type == TYPE_INT || current_function_return_type == TYPE_BOOL) {
                if ($2.is_simple) {
                    if ($2.is_const && !$2.is_id && $2.type == TYPE_INT) {
                        fprintf(output_file, "        sipush %d\n", $2.val.ival);
                    } else if ($2.is_const && !$2.is_id && $2.type == TYPE_BOOL) {
                        fprintf(output_file, "        iconst_%d\n", $2.val.bval ? 1 : 0);
                    } else if ($2.is_id) {
                        SymbolNode *sym = lookup_symbol($2.id_name);
                        if (sym && sym->is_const) {
                            if (sym->type == TYPE_INT)
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                            else if (sym->type == TYPE_BOOL)
                                fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $2.id_name);
                        }
                    }
                }
                // 複雜運算式已經在 stack top
                fprintf(output_file, "        ireturn\n");
            } else if (current_function_return_type == TYPE_VOID) {
                fprintf(output_file, "        return\n");
            }
            // 你可以擴充 string/float 型態
        }

        Trace("Reducing: return_stmt -> return expression ';'");
    }
    | RETURN SEMICOLON
    {
        has_return = 1;
        if (current_function_return_type != TYPE_VOID) {
            char error_msg[100];
            sprintf(error_msg, "Return type mismatch: non-void function must return a value");
            yyerror(error_msg);
            return 1;
        }

        if (output_file)
            fprintf(output_file, "        return\n");
        Trace("Reducing: return_stmt -> return ';'");
    }
    ;

// 一般變數賦值敘述，檢查符號、常數、型態
assign_stmt
    : assign_expr SEMICOLON
    {
        Trace("Reducing: assign_stmt -> assign_expr ';'");
    }
    ;

assign_expr
    : ID ASSIGN expression
    {
        SymbolNode *symbol = lookup_symbol($1);
        if (symbol == NULL) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $1);
            yyerror(error_msg);
            return 1;
        } else if (symbol->is_const) {
            char error_msg[100];
            sprintf(error_msg, "Cannot assign to const symbol: %s", $1);
            yyerror(error_msg);
            return 1;
        } else if (symbol->type != $3.type) {
            char error_msg[100];
            sprintf(error_msg, "Type mismatch in assignment to %s: expected type %d, got type %d", 
                    $1, symbol->type, $3.type);
            yyerror(error_msg);
            return 1;
        }

        if (output_file && symbol->type != TYPE_STRING && symbol->type != TYPE_FLOAT) {
            // 只有在簡單表達式時才生成載入 bytecode
            if ($3.is_simple) {
                if ($3.is_const) {
                    SymbolNode *rhs = NULL;
                    if ($3.is_id) {
                        rhs = lookup_symbol($3.id_name);
                    }
                    int type = rhs ? rhs->type : symbol->type;
                    if (type == TYPE_INT) {
                        int val = rhs ? rhs->value.int_value : $3.val.ival;
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", val);
                        else
                            fprintf(output_file, "        sipush %d\n", val);
                    } else if (type == TYPE_BOOL) {
                        int val = rhs ? rhs->value.bool_value : $3.val.bval;
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        iconst_%d\n", val ? 1 : 0);
                        else
                            fprintf(output_file, "        iconst_%d\n", val ? 1 : 0);
                    }
                } else if ($3.is_id && !$3.is_const) {
                    // 右值是變數（非 const）
                    SymbolNode *rhs = lookup_symbol($3.id_name);
                    if (rhs) {
                        if (rhs->local_var_num >= 0) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        iload %d\n", rhs->local_var_num);
                            else
                                fprintf(output_file, "        iload %d\n", rhs->local_var_num);
                        } else {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        getstatic int %s.%s\n", class_name, $3.id_name);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
            }
            // 複雜表達式的 bytecode 會在 expression 規則中生成
            
            // 決定 istore 或 putstatic (不管是簡單還是複雜表達式都要執行)
            if (symbol->local_var_num >= 0) {
                if (for_update_mode)
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        istore %d\n", symbol->local_var_num);
                else
                    fprintf(output_file, "        istore %d\n", symbol->local_var_num);
            } else {
                if (for_update_mode)
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        putstatic int %s.%s\n", class_name, $1);
                else
                    fprintf(output_file, "        putstatic int %s.%s\n", class_name, $1);
            }
        }

        Trace("Reducing: assign_expr -> ID = expression");
    }
    ;

// 陣列元素賦值敘述，檢查符號、維度、型態
array_assign_stmt
    : ID array_index ASSIGN expression SEMICOLON
    {
        yyerror("This compiler does not support array assignments.");
        return 1;
        SymbolNode *symbol = lookup_symbol($1);
        if (!symbol) {
            char error_msg[100];
            sprintf(error_msg, "Undefined symbol: %s", $1);
            yyerror(error_msg);
            free($2.sizes); // 釋放記憶體
            return 1;
        }
        if (!symbol->is_array) {
            char error_msg[100];
            sprintf(error_msg, "Symbol '%s' is not an array", $1);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        if ($2.dim_count != symbol->dim_count) {
            char error_msg[100];
            sprintf(error_msg, "Array '%s' index dimension mismatch: expected %d, got %d", $1, symbol->dim_count, $2.dim_count);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        for (int i = 0; i < $2.dim_count; ++i) {
            if ($2.sizes[i] < 0 || $2.sizes[i] >= symbol->sizes[i]) {
                char error_msg[100];
                sprintf(error_msg, "Array '%s' index %d out of bounds: %d (size: %d)", $1, i, $2.sizes[i], symbol->sizes[i]);
                yyerror(error_msg);
                free($2.sizes);
                return 1;
            }
        }
        if (symbol->type != $4.type) {
            char error_msg[100];
            sprintf(error_msg, "Type mismatch in array assignment: array '%s' type %d, assigned type %d", $1, symbol->type, $4.type);
            yyerror(error_msg);
            free($2.sizes);
            return 1;
        }
        Trace("Reducing: array_assign_stmt -> ID array_index = expression ';'");
        free($2.sizes);
    }
    ;

// 陣列索引規則，支援多維陣列，檢查索引型態必須為整數
array_index
    : array_index LBRACK expression RBRACK
    {
        yyerror("This compiler does not support array indexing.");
        return 1;
        if ($3.type != TYPE_INT) {
            yyerror("Array index must be integer");
            return 1;
        }
        $$.dim_count = $1.dim_count + 1;
        $$.sizes = realloc($1.sizes, sizeof(int) * $$.dim_count);
        $$.sizes[$1.dim_count] = $3.val.ival;
    }
    | LBRACK expression RBRACK
    {
        yyerror("This compiler does not support array indexing.");
        return 1;
        if ($2.type != TYPE_INT) {
            yyerror("Array index must be integer");
            return 1;
        }
        $$.dim_count = 1;
        $$.sizes = malloc(sizeof(int));
        $$.sizes[0] = $2.val.ival;
    }
    ;

// 運算式規則，支援各種運算與型態檢查
expression
: expression PLUS expression
    {
        $$.is_simple = 0;
        // 運算元型態檢查
        if ($1.type != $3.type) {
            yyerror("Type mismatch in arithmetic expression");
            return 1;
        }
        $$.type = $1.type;
        $$.is_array = 0;

        // 常數折疊
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            if ($1.type == TYPE_INT) {
                $$.val.ival = $1.val.ival + $3.val.ival;
                $$.is_const = 1;
            }
        } else {
            $$.is_const = 0;
            // 根據運算元類型決定如何生成 bytecode
            if (output_file && scope_level > 1) {
                // 如果左運算元是簡單的，需要生成載入指令
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $1.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $1.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                            }
                        }
                    }
                }
                // 如果右運算元是簡單的，需要生成載入指令
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $3.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $3.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                            }
                        }
                    }
                }
                // 最後生成加法指令
                if (for_update_mode)
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        iadd\n");
                else
                    fprintf(output_file, "        iadd\n");
            }
        }
        Trace("Reducing: expression -> expression + expression");
    }
| expression MINUS expression
    {
        $$.is_simple = 0;
        // 減法運算，禁止陣列直接參與運算
        if ($1.is_array || $3.is_array) {
            yyerror("Array cannot be used in arithmetic operations");
            return 1;
        }

        // 運算元型態檢查
        if ($1.type != $3.type) {
            yyerror("Type mismatch in arithmetic expression");
            return 1;
        }

        $$.type = $1.type;
        $$.is_array = 0;

        // 常數折疊
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            if ($1.type == TYPE_INT) {
                $$.val.ival = $1.val.ival - $3.val.ival;
                $$.is_const = 1;
            }
        } else {
            $$.is_const = 0;
            // 生成 bytecode - 使用 swap 修正順序
            if (output_file && scope_level > 1) {
                if ($1.is_simple && $3.is_simple) {
                    // 載入左運算元
                    if ($1.is_const && !$1.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $1.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $1.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                            }
                        }
                    }
                    // 載入右運算元
                    if ($3.is_const && !$3.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $3.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $3.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                            }
                        }
                    }
                }
                else if ($1.is_simple && !$3.is_simple) {
                    // 右運算元結果已在 stack，載入左運算元後需要 swap
                    if ($1.is_const && !$1.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $1.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $1.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                            }
                        }
                    }
                    if (for_update_mode)
                        snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                 "        swap\n");
                    else
                        fprintf(output_file, "        swap\n");
                }
                else if (!$1.is_simple && $3.is_simple) {
                    // 左運算元結果已在 stack，載入右運算元
                    if ($3.is_const && !$3.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $3.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $3.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                            }
                        }
                    }
                }
                // 兩個都複雜：順序已正確

                // 執行減法：stack[top-1] - stack[top]
                if (for_update_mode)
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        isub\n");
                else
                    fprintf(output_file, "        isub\n");
            }
        }
        Trace("Reducing: expression -> expression - expression");
    }
| expression STAR expression
    {
        $$.is_simple = 0;
        // 乘法運算，禁止陣列直接參與運算
        if ($1.is_array || $3.is_array) {
            yyerror("Array cannot be used in arithmetic operations");
            return 1;
        }

        // 運算元型態檢查
        if ($1.type != $3.type) {
            yyerror("Type mismatch in arithmetic expression");
            return 1;
        }

        $$.type = $1.type;
        $$.is_array = 0;

        // 常數折疊
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            if ($1.type == TYPE_INT) {
                $$.val.ival = $1.val.ival * $3.val.ival;
                $$.is_const = 1;
            }
        } else {
            $$.is_const = 0;
            // 生成 bytecode
            if (output_file && scope_level > 1) {
                // 如果左運算元是簡單的，需要生成載入指令
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $1.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $1.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                            }
                        }
                    }
                }
                // 如果右運算元是簡單的，需要生成載入指令
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $3.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $3.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                            }
                        }
                    }
                }
                // 生成乘法指令
                if (for_update_mode)
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        imul\n");
                else
                    fprintf(output_file, "        imul\n");
            }
        }
        Trace("Reducing: expression -> expression * expression");
    }
| expression DIV expression
    {
        $$.is_simple = 0;
        // 除法運算，禁止陣列直接參與運算，檢查除數為0
        if ($1.is_array || $3.is_array) {
            yyerror("Array cannot be used in arithmetic operations");
            return 1;
        }

        // 運算元型態檢查
        if ($1.type != $3.type) {
            yyerror("Type mismatch in arithmetic expression");
            return 1;
        }

        $$.type = $1.type;
        $$.is_array = 0;

        // 常數折疊
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            if ($1.type == TYPE_INT) {
                if ($3.val.ival == 0) {
                    yyerror("Division by zero");
                    return 1;
                }
                $$.val.ival = $1.val.ival / $3.val.ival;
                $$.is_const = 1;
            }
        } else {
            $$.is_const = 0;
            // 生成 bytecode - 使用 swap 修正順序
            if (output_file && scope_level > 1) {
                if ($1.is_simple && $3.is_simple) {
                    // 載入左運算元
                    if ($1.is_const && !$1.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $1.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $1.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                            }
                        }
                    }
                    // 載入右運算元
                    if ($3.is_const && !$3.is_id) {
                        if ($3.val.ival == 0) {
                            yyerror("Division by zero");
                            return 1;
                        }
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $3.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            if (sym->value.int_value == 0) {
                                yyerror("Division by zero");
                                return 1;
                            }
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $3.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                            }
                        }
                    }
                }
                else if ($1.is_simple && !$3.is_simple) {
                    // 右運算元結果已在 stack，載入左運算元後需要 swap
                    if ($1.is_const && !$1.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $1.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $1.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                            }
                        }
                    }
                    if (for_update_mode)
                        snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                 "        swap\n");
                    else
                        fprintf(output_file, "        swap\n");
                }
                else if (!$1.is_simple && $3.is_simple) {
                    // 左運算元結果已在 stack，載入右運算元
                    if ($3.is_const && !$3.is_id) {
                        if ($3.val.ival == 0) {
                            yyerror("Division by zero");
                            return 1;
                        }
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $3.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            if (sym->value.int_value == 0) {
                                yyerror("Division by zero");
                                return 1;
                            }
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $3.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                            }
                        }
                    }
                }
                // 兩個都複雜：順序已正確

                // 執行除法：stack[top-1] / stack[top]
                if (for_update_mode)
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        idiv\n");
                else
                    fprintf(output_file, "        idiv\n");
            }
        }
        Trace("Reducing: expression -> expression / expression");
    }
| expression MOD expression
    {
        $$.is_simple = 0;
        // 取餘數運算，只允許整數
        if ($1.is_array || $3.is_array) {
            yyerror("Array cannot be used in arithmetic operations");
            return 1;
        }

        if ($1.type != TYPE_INT || $3.type != TYPE_INT) {
            yyerror("Modulo operation requires integer operands");
            return 1;
        }

        $$.type = TYPE_INT;
        $$.is_array = 0;

        // 常數折疊
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            if ($3.val.ival == 0) {
                yyerror("Modulo by zero");
                return 1;
            }
            $$.val.ival = $1.val.ival % $3.val.ival;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            // 生成 bytecode - 使用 swap 修正順序
            if (output_file && scope_level > 1) {
                if ($1.is_simple && $3.is_simple) {
                    // 載入左運算元
                    if ($1.is_const && !$1.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $1.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $1.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                            }
                        }
                    }
                    // 載入右運算元
                    if ($3.is_const && !$3.is_id) {
                        if ($3.val.ival == 0) {
                            yyerror("Modulo by zero");
                            return 1;
                        }
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $3.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            if (sym->value.int_value == 0) {
                                yyerror("Modulo by zero");
                                return 1;
                            }
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $3.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                            }
                        }
                    }
                }
                else if ($1.is_simple && !$3.is_simple) {
                    // 右運算元結果已在 stack，載入左運算元後需要 swap
                    if ($1.is_const && !$1.is_id) {
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $1.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $1.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                            }
                        }
                    }
                    if (for_update_mode)
                        snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                 "        swap\n");
                    else
                        fprintf(output_file, "        swap\n");
                }
                else if (!$1.is_simple && $3.is_simple) {
                    // 左運算元結果已在 stack，載入右運算元
                    if ($3.is_const && !$3.is_id) {
                        if ($3.val.ival == 0) {
                            yyerror("Modulo by zero");
                            return 1;
                        }
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", $3.val.ival);
                        else
                            fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            if (sym->value.int_value == 0) {
                                yyerror("Modulo by zero");
                                return 1;
                            }
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        sipush %d\n", sym->value.int_value);
                            else
                                fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0) {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        iload %d\n", sym->local_var_num);
                                else
                                    fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            } else {
                                if (for_update_mode)
                                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                             "        getstatic int %s.%s\n", class_name, $3.id_name);
                                else
                                    fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                            }
                        }
                    }
                }
                // 兩個都複雜：順序已正確

                // 執行取餘數：stack[top-1] % stack[top]
                if (for_update_mode)
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        irem\n");
                else
                    fprintf(output_file, "        irem\n");
            }
        }
        Trace("Reducing: expression -> expression %% expression");
    }
    | expression LT expression
    {
        $$.is_simple = 0;
        if (($1.type == TYPE_INT || $1.type == TYPE_FLOAT) && 
            ($3.type == TYPE_INT || $3.type == TYPE_FLOAT))
            $$.type = TYPE_BOOL;
        else {
            yyerror("Type mismatch in comparison");
            return 1;
        }

        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            $$.val.bval = $1.val.ival < $3.val.ival;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            if (output_file && scope_level > 1) {
                int my_label = label_counter++;
                // 載入左運算元
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                        }
                    }
                }
                // 載入右運算元
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
                // 比較運算
                fprintf(output_file, "        isub\n");
                fprintf(output_file, "        iflt L%d\n", my_label);
                fprintf(output_file, "        iconst_0\n");
                fprintf(output_file, "        goto L%d_end\n", my_label);
                fprintf(output_file, "L%d:\n", my_label);
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "L%d_end:\n", my_label);
            }
        }
        Trace("Reducing: expression -> expression < expression");
    }
    | expression LE expression
    {
        $$.is_simple = 0;
        if (($1.type == TYPE_INT || $1.type == TYPE_FLOAT) && 
            ($3.type == TYPE_INT || $3.type == TYPE_FLOAT))
            $$.type = TYPE_BOOL;
        else {
            yyerror("Type mismatch in comparison");
            return 1;
        }
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            $$.val.bval = $1.val.ival <= $3.val.ival;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            if (output_file && scope_level > 1) {
                int my_label = label_counter++;
                // 載入左、右運算元同上
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                        }
                    }
                }
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
                fprintf(output_file, "        isub\n");
                fprintf(output_file, "        ifle L%d\n", my_label);
                fprintf(output_file, "        iconst_0\n");
                fprintf(output_file, "        goto L%d_end\n", my_label);
                fprintf(output_file, "L%d:\n", my_label);
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "L%d_end:\n", my_label);
            }
        }
        Trace("Reducing: expression -> expression <= expression");
    }
    | expression GT expression
    {
        $$.is_simple = 0;
        if (($1.type == TYPE_INT || $1.type == TYPE_FLOAT) && 
            ($3.type == TYPE_INT || $3.type == TYPE_FLOAT))
            $$.type = TYPE_BOOL;
        else {
            yyerror("Type mismatch in comparison");
            return 1;
        }
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            $$.val.bval = $1.val.ival > $3.val.ival;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            if (output_file && scope_level > 1) {
                int my_label = label_counter++;
                // 載入左、右運算元同上
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                        }
                    }
                }
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
                fprintf(output_file, "        isub\n");
                fprintf(output_file, "        ifgt L%d\n", my_label);
                fprintf(output_file, "        iconst_0\n");
                fprintf(output_file, "        goto L%d_end\n", my_label);
                fprintf(output_file, "L%d:\n", my_label);
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "L%d_end:\n", my_label);
            }
        }
        Trace("Reducing: expression -> expression > expression");
    }
    | expression GE expression
    {
        $$.is_simple = 0;
        if (($1.type == TYPE_INT || $1.type == TYPE_FLOAT) && 
            ($3.type == TYPE_INT || $3.type == TYPE_FLOAT))
            $$.type = TYPE_BOOL;
        else {
            yyerror("Type mismatch in comparison");
            return 1;
        }
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            $$.val.bval = $1.val.ival >= $3.val.ival;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            if (output_file && scope_level > 1) {
                int my_label = label_counter++;
                // 載入左、右運算元同上
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                        }
                    }
                }
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
                fprintf(output_file, "        isub\n");
                fprintf(output_file, "        ifge L%d\n", my_label);
                fprintf(output_file, "        iconst_0\n");
                fprintf(output_file, "        goto L%d_end\n", my_label);
                fprintf(output_file, "L%d:\n", my_label);
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "L%d_end:\n", my_label);
            }
        }
        Trace("Reducing: expression -> expression >= expression");
    }
    | expression EQ expression
    {
        $$.is_simple = 0;
        if ($1.type == $3.type)
            $$.type = TYPE_BOOL;
        else {
            yyerror("Type mismatch in equality comparison");
            return 1;
        }
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            $$.val.bval = ($1.type == TYPE_INT) ? ($1.val.ival == $3.val.ival) : 0;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            if (output_file && scope_level > 1) {
                int my_label = label_counter++;
                // 載入左、右運算元同上
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                        }
                    }
                }
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
                fprintf(output_file, "        isub\n");
                fprintf(output_file, "        ifeq L%d\n", my_label);
                fprintf(output_file, "        iconst_0\n");
                fprintf(output_file, "        goto L%d_end\n", my_label);
                fprintf(output_file, "L%d:\n", my_label);
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "L%d_end:\n", my_label);
            }
        }
        Trace("Reducing: expression -> expression == expression");
    }
    | expression NE expression
    {
        $$.is_simple = 0;
        if ($1.type == $3.type)
            $$.type = TYPE_BOOL;
        else {
            yyerror("Type mismatch in inequality comparison");
            return 1;
        }
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            $$.val.bval = ($1.type == TYPE_INT) ? ($1.val.ival != $3.val.ival) : 0;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            if (output_file && scope_level > 1) {
                int my_label = label_counter++;
                // 載入左、右運算元同上
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        fprintf(output_file, "        sipush %d\n", $1.val.ival);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                        }
                    }
                }
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        sipush %d\n", $3.val.ival);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        sipush %d\n", sym->value.int_value);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
                fprintf(output_file, "        isub\n");
                fprintf(output_file, "        ifne L%d\n", my_label);
                fprintf(output_file, "        iconst_0\n");
                fprintf(output_file, "        goto L%d_end\n", my_label);
                fprintf(output_file, "L%d:\n", my_label);
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "L%d_end:\n", my_label);
            }
        }
        Trace("Reducing: expression -> expression != expression");
    }
    | expression AND expression
    {
        $$.is_simple = 0;
        // 邏輯 AND 運算，需要布林操作數
        if ($1.is_array || $3.is_array) {
            yyerror("Array cannot be used in logical operations");
            return 1;
        }

        if ($1.type != TYPE_BOOL || $3.type != TYPE_BOOL) {
            yyerror("Logical AND requires boolean operands");
            return 1;
        }

        $$.type = TYPE_BOOL;
        $$.is_array = 0;

        // 常數折疊
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            $$.val.bval = $1.val.bval && $3.val.bval;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            // 生成 bytecode
            if (output_file && scope_level > 1) {
                // 如果左運算元是簡單的，需要生成載入指令
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        fprintf(output_file, "        iconst_%d\n", $1.val.bval ? 1 : 0);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                        }
                    }
                }
                // 如果右運算元是簡單的，需要生成載入指令
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        iconst_%d\n", $3.val.bval ? 1 : 0);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
                // AND 運算：兩個值相乘，只有都是1時結果才是1
                fprintf(output_file, "        imul\n");
            }
        }
        
        Trace("Reducing: expression -> expression && expression");
    }
    | expression OR expression
    {
        $$.is_simple = 0;
        // 邏輯 OR 運算，需要布林操作數
        if ($1.is_array || $3.is_array) {
            yyerror("Array cannot be used in logical operations");
            return 1;
        }

        if ($1.type != TYPE_BOOL || $3.type != TYPE_BOOL) {
            yyerror("Logical OR requires boolean operands");
            return 1;
        }

        $$.type = TYPE_BOOL;
        $$.is_array = 0;

        // 常數折疊
        if (assign_to_const == 1 && $1.is_const && $3.is_const && !$1.is_id && !$3.is_id) {
            $$.val.bval = $1.val.bval || $3.val.bval;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            // 生成 bytecode
            if (output_file && scope_level > 1) {
                // 如果左運算元是簡單的，需要生成載入指令
                if ($1.is_simple) {
                    if ($1.is_const && !$1.is_id) {
                        fprintf(output_file, "        iconst_%d\n", $1.val.bval ? 1 : 0);
                    } else if ($1.is_id) {
                        SymbolNode *sym = lookup_symbol($1.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                        }
                    }
                }
                // 如果右運算元是簡單的，需要生成載入指令
                if ($3.is_simple) {
                    if ($3.is_const && !$3.is_id) {
                        fprintf(output_file, "        iconst_%d\n", $3.val.bval ? 1 : 0);
                    } else if ($3.is_id) {
                        SymbolNode *sym = lookup_symbol($3.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                        }
                    }
                }
                // OR 運算：相加後限制最大值為1
                fprintf(output_file, "        iadd\n");
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "        invokestatic int java.lang.Math.min(int, int)\n");
            }
        }
        
        Trace("Reducing: expression -> expression || expression");
    }
    | LPAREN expression RPAREN
    {
        $$.type = $2.type;
        $$.is_const = $2.is_const;
        $$.val = $2.val;
        $$.is_simple = $2.is_simple;
        $$.is_id = $2.is_id;
        $$.id_name = $2.id_name;
        $$.is_array = $2.is_array;
        $$.dim_count = $2.dim_count;
        $$.sizes = $2.sizes;
        Trace("Reducing: expression -> ( expression )");
    }
    | MINUS expression %prec UMINUS
    {
        $$.is_simple = 0;
        // 一元負號運算，禁止陣列參與運算
        if ($2.is_array) {
            yyerror("Array cannot be used in arithmetic operations");
            return 1;
        }

        // 檢查運算元型態（只允許整數型態）
        if ($2.type != TYPE_INT) {
            yyerror("Unary minus requires integer operand");
            return 1;
        }

        $$.type = TYPE_INT;
        $$.is_array = 0;

        // 常數運算可直接計算結果（常數折疊）
        if (assign_to_const == 1 && $2.is_const && !$2.is_id) {
            $$.val.ival = -$2.val.ival;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            // 生成 bytecode（只有在非常數折疊且在 scope_level > 1 時）
            if (output_file && scope_level > 1) {
                // 載入運算元
                if ($2.is_const && !$2.is_id) {
                    int val = $2.val.ival;
                    if (for_update_mode)
                        snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                 "        sipush %d\n", val);
                    else
                        fprintf(output_file, "        sipush %d\n", val);
                } else if ($2.is_id) {
                    SymbolNode *sym = lookup_symbol($2.id_name);
                    if (sym && sym->is_const) {
                        int val = sym->value.int_value;
                        if (for_update_mode)
                            snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                     "        sipush %d\n", val);
                        else
                            fprintf(output_file, "        sipush %d\n", val);
                    } else if (sym) {
                        if (sym->local_var_num >= 0) {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                        } else {
                            if (for_update_mode)
                                snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                                         "        getstatic int %s.%s\n", class_name, $2.id_name);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $2.id_name);
                        }
                    }
                }
                // 負號運算指令
                if (for_update_mode)
                    snprintf(for_update_code + strlen(for_update_code), sizeof(for_update_code) - strlen(for_update_code),
                             "        ineg\n");
                else
                    fprintf(output_file, "        ineg\n");
            }
        }
        Trace("Reducing: expression -> - expression");
    }
    | NOT expression
    {
        $$.is_simple = 0;
        // 邏輯 NOT，僅允許布林型態
        if ($2.is_array) {
            yyerror("Array cannot be used in logical operations");
            return 1;
        }

        if ($2.type != TYPE_BOOL) {
            yyerror("Logical NOT requires boolean operand");
            return 1;
        }
        
        $$.type = TYPE_BOOL;
        $$.is_array = 0;

        // 常數折疊
        if (assign_to_const == 1 && $2.is_const && !$2.is_id) {
            $$.val.bval = !$2.val.bval;
            $$.is_const = 1;
        } else {
            $$.is_const = 0;
            // 生成 bytecode
            if (output_file && scope_level > 1) {
                // 如果運算元是簡單的，需要生成載入指令
                if ($2.is_simple) {
                    if ($2.is_const && !$2.is_id) {
                        fprintf(output_file, "        iconst_%d\n", $2.val.bval ? 1 : 0);
                    } else if ($2.is_id) {
                        SymbolNode *sym = lookup_symbol($2.id_name);
                        if (sym && sym->is_const) {
                            fprintf(output_file, "        iconst_%d\n", sym->value.bool_value ? 1 : 0);
                        } else if (sym) {
                            if (sym->local_var_num >= 0)
                                fprintf(output_file, "        iload %d\n", sym->local_var_num);
                            else
                                fprintf(output_file, "        getstatic int %s.%s\n", class_name, $2.id_name);
                        }
                    }
                }
                // 複雜表達式的結果已在 stack 上
                
                // NOT 運算：與1做XOR，0變1，1變0
                fprintf(output_file, "        iconst_1\n");
                fprintf(output_file, "        ixor\n");
            }
        }
        
        Trace("Reducing: expression -> !expression");
    }
    | INTCONST
    {
        // 整數常數
        $$.type = TYPE_INT;
        $$.is_const = 1;
        $$.val.ival = $1;
        $$.is_simple = 1;
        $$.is_id = 0;
      }
    | REALCONST
    {
        // 浮點數常數
        $$.type = TYPE_FLOAT;
        $$.is_const = 1;
        $$.val.sval = $1;
        $$.is_id = 0;
    }
    | STRINGCONST
    {
        // 字串常數
        $$.type = TYPE_STRING;
        $$.is_const = 1;
        $$.val.sval = $1;
        $$.is_id = 0;
    }
    | TRUE
    {
        // 布林常數 true
        $$.type = TYPE_BOOL;
        $$.is_const = 1;
        $$.val.bval = 1;
        $$.is_simple = 1;
        $$.is_array = 0; 
        $$.is_id = 0; 
    }
    | FALSE
    {
         // 布林常數 false
        $$.type = TYPE_BOOL;
        $$.is_const = 1;
        $$.val.bval = 0;
        $$.is_simple = 1;
        $$.is_array = 0;  // 加上這行
        $$.is_id = 0; 
    }
    | ID
    {
        // 變數名稱，查符號表
        SymbolNode *symbol = lookup_symbol($1);
        if (!symbol) {
            yyerror("Undefined symbol");
            return 1;
        }
        $$.type = symbol->type;
        $$.is_const = symbol->is_const;
        $$.is_array = symbol->is_array;
        $$.dim_count = symbol->dim_count;
        $$.sizes = symbol->is_array ? symbol->sizes : NULL;
        $$.is_id = 1;         
        $$.id_name = $1;
        $$.is_simple = 1;
    }
    | ID array_index
    {
        yyerror("This compiler does not support array element access.");
        return 1;
        // 陣列元素取值
        SymbolNode *symbol = lookup_symbol($1);
        if (!symbol) {
            yyerror("Undefined symbol");
            return 1;
        }
        if (!symbol->is_array) {
            yyerror("Variable is not an array");
            return 1;
        }
        if ($2.dim_count != symbol->dim_count) {
            yyerror("Array index dimension mismatch");
            return 1;
        }
        // 檢查 index 範圍
        for (int i = 0; i < $2.dim_count; ++i) {
            if ($2.sizes[i] < 0 || $2.sizes[i] >= symbol->sizes[i]) {
                yyerror("Array index out of bounds");
                return 1;
            }
        }
        $$.type = symbol->type;
        $$.is_const = 0;
        $$.is_array = 0;
        $$.dim_count = 0;
        $$.sizes = NULL;
        free($2.sizes);
    }
    | func_call
    ;

// 函數呼叫
func_call
    : ID LPAREN expr_list_opt RPAREN
    {
        // 檢查函數是否存在、參數型態與數量是否正確
        FunctionNode *fn = lookup_function($1);
        if (!fn) {
            char error_msg[100];
            sprintf(error_msg, "Function '%s' not defined", $1);
            yyerror(error_msg);
            return 1;
        }
        // 比對參數型別與數量
        ParamNode *formal = fn->params;
        ParamNode *actual = $3; // expr_list_opt 的 $$ 設為 ParamNode* 或 NULL
        int idx = 1;
        while (formal && actual) {
            if (formal->is_array) {
                if (!actual->is_array) {
                    char error_msg[100];
                    sprintf(error_msg, "Function '%s' argument %d: expected array", $1, idx);
                    yyerror(error_msg);
                    return 1;
                }
                if (formal->type != actual->type) {
                    char error_msg[100];
                    sprintf(error_msg, "Function '%s' argument %d: array type mismatch (expected %d, got %d)", $1, idx, formal->type, actual->type);
                    yyerror(error_msg);
                    return 1;
                }
                if (formal->dim_count != actual->dim_count) {
                    char error_msg[100];
                    sprintf(error_msg, "Function '%s' argument %d: array dimension mismatch (expected %d, got %d)", $1, idx, formal->dim_count, actual->dim_count);
                    yyerror(error_msg);
                    return 1;
                }
                for (int i = 0; i < formal->dim_count; ++i) {
                    if (formal->sizes[i] != actual->sizes[i]) {
                        char error_msg[100];
                        sprintf(error_msg, "Function '%s' argument %d: array size mismatch at dimension %d (expected %d, got %d)", $1, idx, i+1, formal->sizes[i], actual->sizes[i]);
                        yyerror(error_msg);
                        return 1;
                    }
                }
            } else {
                if (formal->type != actual->type) {
                    char error_msg[100];
                    sprintf(error_msg, "Function '%s' argument %d type mismatch: expected %d, got %d", $1, idx, formal->type, actual->type);
                    yyerror(error_msg);
                    return 1;
                }
            }
            formal = formal->next;
            actual = actual->next;
            idx++;
        }
        if (formal || actual) {
            char error_msg[100];
            sprintf(error_msg, "Function '%s' argument count mismatch", $1);
            yyerror(error_msg);
            return 1;
        }

        // 產生 invokestatic 指令
        if (output_file && scope_level > 1) {
            char param_types[128] = "";
            ParamNode *p = fn->params;
            while (p) {
                if (strlen(param_types) > 0) strcat(param_types, ", ");
                switch (p->type) {
                    case TYPE_INT: strcat(param_types, "int"); break;
                    case TYPE_FLOAT: strcat(param_types, "float"); break;
                    case TYPE_BOOL: strcat(param_types, "boolean"); break;
                    case TYPE_STRING: strcat(param_types, "java.lang.String"); break;
                }
                p = p->next;
            }
            char *ret_type = "";
            switch (fn->return_type) {
                case TYPE_INT: ret_type = "int"; break;
                case TYPE_FLOAT: ret_type = "float"; break;
                case TYPE_BOOL: ret_type = "boolean"; break;
                case TYPE_STRING: ret_type = "java.lang.String"; break;
                case TYPE_VOID: ret_type = "void"; break;
            }
            fprintf(output_file, "        invokestatic %s %s.%s(%s)\n", ret_type, class_name, $1, param_types);
        }

        $$.type = fn->return_type;
        $$.is_const = 0;
        free_param_list($3);
    }
    ;

// 可選的參數串列（允許空）
expr_list_opt
    : expr_list
    {
        $$ = $1;
        Trace("Reducing: expr_list_opt -> expr_list");
    }
    | /* empty */
    {
        $$ = NULL;
        Trace("Reducing: expr_list_opt -> (empty)");
    }
    ;

// 參數串列
expr_list
    : expr_list COMMA expression
    {
        ParamNode *tail = $1;
        while (tail->next) tail = tail->next;
        ParamNode *new_param = (ParamNode*)malloc(sizeof(ParamNode));
        new_param->type = $3.type;
        new_param->name = NULL;
        new_param->next = NULL;
        new_param->is_array = $3.is_array;
        new_param->dim_count = $3.dim_count;
        if ($3.is_array && $3.dim_count > 0 && $3.sizes) {
            new_param->sizes = malloc(sizeof(int) * $3.dim_count);
            for (int i = 0; i < $3.dim_count; ++i)
                new_param->sizes[i] = $3.sizes[i];
        } else {
            new_param->sizes = NULL;
        }
        // 參數 bytecode 生成
        if (output_file && scope_level > 1) {
            if ($3.is_const && !$3.is_id && $3.type == TYPE_INT) {
                fprintf(output_file, "        sipush %d\n", $3.val.ival);
            } else if ($3.is_const && $3.is_id && $3.type == TYPE_INT) {
                SymbolNode *sym = lookup_symbol($3.id_name);
                if (sym && sym->is_const)
                    fprintf(output_file, "        sipush %d\n", sym->value.int_value);
            } else if ($3.is_id && !$3.is_const) {
                SymbolNode *sym = lookup_symbol($3.id_name);
                if (sym) {
                    if (sym->local_var_num >= 0)
                        fprintf(output_file, "        iload %d\n", sym->local_var_num);
                    else
                        fprintf(output_file, "        getstatic int %s.%s\n", class_name, $3.id_name);
                }
            } else if ($3.is_const && $3.type == TYPE_BOOL) {
                fprintf(output_file, "        iconst_%d\n", $3.val.bval ? 1 : 0);
            }
            // 你可以擴充 STRING/FLOAT 型態
        }
        tail->next = new_param;
        $$ = $1;
        Trace("Reducing: expr_list -> expr_list ',' expression");
    }
    | expression
    {
        ParamNode *new_param = (ParamNode*)malloc(sizeof(ParamNode));
        new_param->type = $1.type;
        new_param->name = NULL;
        new_param->next = NULL;
        new_param->is_array = $1.is_array;
        new_param->dim_count = $1.dim_count;
        if ($1.is_array && $1.dim_count > 0 && $1.sizes) {
            new_param->sizes = malloc(sizeof(int) * $1.dim_count);
            for (int i = 0; i < $1.dim_count; ++i)
                new_param->sizes[i] = $1.sizes[i];
        } else {
            new_param->sizes = NULL;
        }
        // 參數 bytecode 生成
        if (output_file && scope_level > 1) {
            if ($1.is_const && !$1.is_id && $1.type == TYPE_INT) {
                fprintf(output_file, "        sipush %d\n", $1.val.ival);
            } else if ($1.is_const && $1.is_id && $1.type == TYPE_INT) {
                SymbolNode *sym = lookup_symbol($1.id_name);
                if (sym && sym->is_const)
                    fprintf(output_file, "        sipush %d\n", sym->value.int_value);
            } else if ($1.is_id && !$1.is_const) {
                SymbolNode *sym = lookup_symbol($1.id_name);
                if (sym) {
                    if (sym->local_var_num >= 0)
                        fprintf(output_file, "        iload %d\n", sym->local_var_num);
                    else
                        fprintf(output_file, "        getstatic int %s.%s\n", class_name, $1.id_name);
                }
            } else if ($1.is_const && $1.type == TYPE_BOOL) {
                fprintf(output_file, "        iconst_%d\n", $1.val.bval ? 1 : 0);
            }
            // 你可以擴充 STRING/FLOAT 型態
        }
        $$ = new_param;
        Trace("Reducing: expr_list -> expression");
    }
    ;

%%
// 進入新的作用域
void enter_scope() {
    ScopeNode *new_scope = (ScopeNode *)malloc(sizeof(ScopeNode));
    new_scope->symbols = NULL;
    new_scope->parent = current_scope;
    // 新增：繼承上一層的 next_local_var_num
    if (current_scope)
        new_scope->next_local_var_num = current_scope->next_local_var_num;
    else
        new_scope->next_local_var_num = 0;
    current_scope = new_scope;
    scope_level++;
    printf(">> Entering block, next number %d\n", current_scope->next_local_var_num);
}
// 離開當前作用域
void exit_scope() {
    if (current_scope == NULL) {
        printf("Error: No scope to exit\n");
        return;
    }

    // 先印出 leaving block, symbol table entries
    printf("leaving block, symbol table entries:\n");
    SymbolNode *current = current_scope->symbols;
    while (current != NULL) {
        // 只印 int 變數且不是 const，也不是 array
        if (!current->is_array && current->type == TYPE_INT && !current->is_const) {
            printf("<\"%s\", variable, integer, %d>\n", current->name, current->local_var_num);
        }
        current = current->next;
    }

    // 印出完整符號表
    printf("\nSymbol Table:\n");
    printf("-------------------------------------------------------------------------------\n");
    printf("Name\t\tType\t\tConst\tArray\tDims\tSizes\t\tValue\n");
    printf("-------------------------------------------------------------------------------\n");

    current = current_scope->symbols;
    while (current != NULL) {
        printf("%s\t\t", current->name);

        // Type
        switch (current->type) {
            case TYPE_INT:    printf("INT\t\t"); break;
            case TYPE_FLOAT:  printf("FLOAT\t\t"); break;
            case TYPE_STRING: printf("STRING\t\t"); break;
            case TYPE_BOOL:   printf("BOOL\t\t"); break;
            case TYPE_VOID:   printf("VOID\t\t"); break;
            default:          printf("UNKNOWN\t\t"); break;
        }

        // Const
        printf("%d\t", current->is_const);

        // Array info
        printf("%s\t", current->is_array ? "Y" : "N");
        if (current->is_array) {
            printf("%d\t", current->dim_count);
            for (int i = 0; i < current->dim_count; ++i)
                printf("%d ", current->sizes[i]);
            printf("\t");
        } else {
            printf("-\t-\t\t");
        }

        // Value
        if (!current->is_array && current->is_const) {
            switch (current->type) {
                case TYPE_INT:
                    printf("%d", current->value.int_value);
                    break;
                case TYPE_FLOAT:
                    printf("%.2f", current->value.float_value);
                    break;
                case TYPE_STRING:
                    if (current->value.string_value)
                        printf("\"%s\"", current->value.string_value);
                    break;
                case TYPE_BOOL:
                    printf("%s", current->value.bool_value ? "true" : "false");
                    break;
                default:
                    break;
            }
        }
        printf("\n");
        current = current->next;
    }

    printf("-------------------------------------------------------------------------------\n");

    // 釋放當前作用域中的所有符號
    current = current_scope->symbols;
    SymbolNode *temp;
    while (current != NULL) {
        temp = current;
        current = current->next;
        free(temp->name);

        if (temp->type == TYPE_STRING && temp->is_const && temp->value.string_value)
            free(temp->value.string_value);

        if (temp->is_array && temp->sizes)
            free(temp->sizes);

        free(temp);
    }

    // 返回上一層作用域
    ScopeNode *parent = current_scope->parent;
    free(current_scope);
    current_scope = parent;
    scope_level--;

    printf(">> Exiting to scope level %d\n", scope_level);
}

// 在所有作用域中查詢符號
SymbolNode* lookup_symbol(char *name) {
    ScopeNode *scope = current_scope;
    
    while (scope != NULL) {
        SymbolNode *current = scope->symbols;
        
        while (current != NULL) {
            if (strcmp(current->name, name) == 0) {
                return current;  // 找到符號
            }
            current = current->next;
        }
        
        scope = scope->parent;  // 移到上一層作用域
    }
    
    return NULL;  // 沒有找到符號
}

// 只在當前作用域中查詢符號
SymbolNode* lookup_symbol_in_current_scope(char *name) {
    if (current_scope == NULL) {
        return NULL;
    }
    
    SymbolNode *current = current_scope->symbols;
    
    while (current != NULL) {
        if (strcmp(current->name, name) == 0) {
            return current;  // 找到符號
        }
        current = current->next;
    }
    
    return NULL;  // 沒有找到符號
}

// 在當前作用域中插入符號
void insert_symbol(char *name, int type, int is_const) {
    // 檢查符號是否已經存在於當前作用域
    if (lookup_symbol_in_current_scope(name) != NULL) {
        char error_msg[100];
        sprintf(error_msg, "Symbol '%s' already defined in current scope", name);
        yyerror(error_msg);
        exit(1);
    }
    
    // 創建新的符號節點
    SymbolNode *new_symbol = (SymbolNode *)malloc(sizeof(SymbolNode));
    new_symbol->name = strdup(name);
    new_symbol->type = type;
    new_symbol->is_const = is_const;
    new_symbol->is_array = 0;
    new_symbol->dim_count = 0;
    new_symbol->sizes = NULL;

    // 這裡加上 local_var_num 處理
    new_symbol->local_var_num = -1; // 預設
    // 只對非全域變數給 local var 編號
    if (scope_level > 1 && !is_const) {
        new_symbol->local_var_num = current_scope->next_local_var_num;
        current_scope->next_local_var_num++;
        printf("%s = %d, next number %d\n", name, new_symbol->local_var_num, current_scope->next_local_var_num);
    }

    // 初始化常數值（將在後面設置）
    if (type == TYPE_INT) {
        new_symbol->value.int_value = -1;
    } else if (type == TYPE_FLOAT) {
        new_symbol->value.float_value = -1.0;
    } else if (type == TYPE_STRING) {
        new_symbol->value.string_value = strdup("n/a");
    } else if (type == TYPE_BOOL) {
        new_symbol->value.bool_value = 0;
    }
    
    // 將新符號插入當前作用域的符號串列頭部
    if (current_scope == NULL) {
        enter_scope();  // 如果還沒有作用域，創建一個
    }
    
    new_symbol->next = current_scope->symbols;
    current_scope->symbols = new_symbol;
    
    printf(">> Inserted symbol: %s (type=%d, const=%d) in scope level %d\n", 
           name, type, is_const, scope_level);
}

// 設置常數的值
void set_const_value(char *name, int type, void *value) {
    SymbolNode *symbol = lookup_symbol_in_current_scope(name);
    if (symbol == NULL) {
        return;
    }
    
    switch (type) {
        case TYPE_INT:
            symbol->value.int_value = *((int*)value);
            break;
        case TYPE_FLOAT:
            symbol->value.float_value = *((float*)value);
            break;
        case TYPE_STRING:
            if (symbol->value.string_value) {
                free(symbol->value.string_value);
            }
            symbol->value.string_value = strdup((char*)value);
            break;
        case TYPE_BOOL:
            symbol->value.bool_value = *((int*)value);
            break;
    }
}

// 顯示符號表
void dump_symbol_table() {
    printf("\nSymbol Table:\n");
    printf("-------------------------------------------------------------------------------\n");
    printf("Name\t\tType\t\tConst\tArray\tDims\tSizes\t\tValue\n");
    printf("-------------------------------------------------------------------------------\n");

    ScopeNode *scope = current_scope;
    int level = scope_level;

    while (scope != NULL) {
        printf("Scope Level %d:\n", level);

        SymbolNode *current = scope->symbols;

        while (current != NULL) {
            printf("%s\t\t", current->name);

            // Type
            switch (current->type) {
                case TYPE_INT:    printf("INT\t\t"); break;
                case TYPE_FLOAT:  printf("FLOAT\t\t"); break;
                case TYPE_STRING: printf("STRING\t\t"); break;
                case TYPE_BOOL:   printf("BOOL\t\t"); break;
                case TYPE_VOID:   printf("VOID\t\t"); break;
                default:          printf("UNKNOWN\t\t"); break;
            }

            // Const
            printf("%d\t", current->is_const);

            // Array info
            printf("%s\t", current->is_array ? "Y" : "N");
            if (current->is_array) {
                printf("%d\t", current->dim_count);
                for (int i = 0; i < current->dim_count; ++i)
                    printf("%d ", current->sizes[i]);
                printf("\t");
            } else {
                printf("-\t-\t\t");
            }

            // Value
            if (!current->is_array && current->is_const) {
                switch (current->type) {
                    case TYPE_INT:
                        printf("%d", current->value.int_value);
                        break;
                    case TYPE_FLOAT:
                        printf("%.2f", current->value.float_value);
                        break;
                    case TYPE_STRING:
                        if (current->value.string_value)
                            printf("\"%s\"", current->value.string_value);
                        break;
                    case TYPE_BOOL:
                        printf("%s", current->value.bool_value ? "true" : "false");
                        break;
                    default:
                        break;
                }
            }
            printf("\n");
            current = current->next;
        }

        printf("\n");
        scope = scope->parent;
        level--;
    }

    printf("-------------------------------------------------------------------------------\n");
}

// 插入函數到函數表
void insert_function(char *name, int return_type, ParamNode *params) {
    // 檢查是否已存在
    FunctionNode *curr = function_table;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            char error_msg[100];
            sprintf(error_msg, "Function '%s' already defined", name);
            yyerror(error_msg);
            exit(1);
        }
        curr = curr->next;
    }
    FunctionNode *fn = (FunctionNode*)malloc(sizeof(FunctionNode));
    fn->name = strdup(name);
    fn->return_type = return_type;
    fn->params = params;
    fn->next = function_table;
    function_table = fn;
}

// 查詢函數表
FunctionNode* lookup_function(char *name) {
    FunctionNode *curr = function_table;
    while (curr) {
        if (strcmp(curr->name, name) == 0)
            return curr;
        curr = curr->next;
    }
    return NULL;
}

// 建立參數節點
ParamNode* make_param(int type, char *name) {
    ParamNode *p = (ParamNode*)malloc(sizeof(ParamNode));
    p->type = type;
    p->name = strdup(name);
    p->is_array = 0;
    p->dim_count = 0;
    p->sizes = NULL;
    p->next = NULL;
    return p;
}

// 顯示函數表
void dump_function_table() {
    printf("\nFunction Table:\n");
    printf("--------------------------------------------------\n");
    printf("Name\t\tReturn Type\tParam Count\n");
    printf("--------------------------------------------------\n");
    FunctionNode *fn = function_table;
    while (fn) {
        int param_count = 0;
        ParamNode *p = fn->params;
        while (p) {
            param_count++;
            p = p->next;
        }
        printf("%s\t\t%d\t\t%d\n", fn->name, fn->return_type, param_count);
        fn = fn->next;
    }
    printf("--------------------------------------------------\n");
}

// 插入陣列符號
void insert_array_symbol(char *name, int type, int dim_count, int *sizes) {
    if (lookup_symbol_in_current_scope(name) != NULL) {
        char error_msg[100];
        sprintf(error_msg, "Array symbol '%s' already defined in current scope", name);
        yyerror(error_msg);
        exit(1);
    }
    SymbolNode *new_symbol = (SymbolNode *)malloc(sizeof(SymbolNode));
    new_symbol->name = strdup(name);
    new_symbol->type = type;
    new_symbol->is_const = 0;
    new_symbol->is_array = 1;
    new_symbol->dim_count = dim_count;
    new_symbol->sizes = malloc(sizeof(int) * dim_count);
    for (int i = 0; i < dim_count; ++i)
        new_symbol->sizes[i] = sizes[i];
    new_symbol->next = current_scope->symbols;
    current_scope->symbols = new_symbol;
    printf(">> Inserted array symbol: %s (type=%d, dims=%d) in scope level %d\n",
           name, type, dim_count, scope_level);
}

// 釋放參數串列
void free_param_list(ParamNode *p) {
    while (p) {
        ParamNode *next = p->next;
        if (p->sizes) free(p->sizes);
        if (p->name) free(p->name);
        free(p);
        p = next;
    }
}

// 釋放所有作用域與符號
void free_all_scopes() {
    while (current_scope) {
        // 只做釋放，不印
        SymbolNode *current = current_scope->symbols;
        SymbolNode *temp;
        while (current != NULL) {
            temp = current;
            current = current->next;
            free(temp->name);
            if (temp->type == TYPE_STRING && temp->is_const && temp->value.string_value)
                free(temp->value.string_value);
            if (temp->is_array && temp->sizes)
                free(temp->sizes);
            free(temp);
        }
        ScopeNode *parent = current_scope->parent;
        free(current_scope);
        current_scope = parent;
    }
}

// 函數處理語法錯誤 
void yyerror(const char *msg) {
    fprintf(stderr, "Syntax Error: %s\n", msg);
}

void generate_class_header() {
    fprintf(output_file, "class %s\n{\n", class_name);
}

void generate_class_footer() {
    fprintf(output_file, "}\n");
}


// main 函數 
int main(int argc, char **argv) {
    // 檢查是否提供了輸入文件
    if (argc > 1) {
        // Open file and set as input
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            perror("Error opening file");
            return 1;
        }
        
        // Extract class name from filename (remove path and extension)
        char *filename = argv[1];
        char *base_name = strrchr(filename, '/');
        if (!base_name) base_name = strrchr(filename, '\\');
        if (base_name) {
            base_name++; // Skip the slash
        } else {
            base_name = filename;
        }
        
        // Copy the base name and remove extension
        strcpy(class_name, base_name);
        char *dot = strrchr(class_name, '.');
        if (dot) *dot = '\0';
        
        // Create output file with .jasm extension (Jasmin assembly)
        char output_filename[300];
        sprintf(output_filename, "%s.jasm", class_name);
        output_file = fopen(output_filename, "w");
        if (!output_file) {
            perror("Error creating output file");
            fclose(yyin);
            return 1;
        }
        generate_class_header();
    } else {
        // If no file provided, read from standard input
        yyin = stdin;
        strcpy(class_name, "Program"); // Default class name
        output_file = fopen("Program.j", "w");
        if (!output_file) {
            perror("Error creating output file");
            return 1;
        }
    }

    // 呼叫 yyparse() 來開始語法分析
    if (yyparse() == 0) {
        // 先檢查是否有 void main()
        FunctionNode *fn = function_table;
        int found = 0;
        while (fn) {
            if (fn->return_type == TYPE_VOID && strcmp(fn->name, "main") == 0) {
                found = 1;
                break;
            }
            fn = fn->next;
        }
        if (!found) {
            fprintf(stderr, "Error: Function 'main' with return type void not defined.\n");
            exit(1);
        }
        // 有 void main() 才印出成功與符號表
        printf("Parsing successful\n");
        dump_symbol_table();
        dump_function_table();
    } else {
        printf("Parsing failed\n");
    }

    // 關閉檔案，如果有的話
    if (yyin != stdin) {
        fclose(yyin);
    }

    free_all_scopes();
    // 釋放 function_table 及其參數串列
    FunctionNode *fn = function_table;
    while (fn) {
        FunctionNode *next = fn->next;
        if (fn->name) free(fn->name);
        free_param_list(fn->params);
        free(fn);
        fn = next;
    }

    if (output_file) {
        fclose(output_file);
    }

    return 0;
}
