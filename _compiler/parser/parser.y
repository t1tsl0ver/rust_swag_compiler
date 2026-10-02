%%
/* 
 * ОБЪЯВЛЕНИЕ ТОКЕНОВ
 */

/* Ключевые слова */
%token UNDERSCORE AS ASYNC AWAIT BREAK CONST CONTINUE CRATE DYN ELSE ENUM 
%token EXTERN FALSE FN FOR IF IMPL IN LET LOOP MATCH MOD MOVE MUT PUB REF 
%token RETURN SELF_VALUE SELF_TYPE STATIC STRUCT SUPER TRAIT TRUE TYPE 
%token UNSAFE USE WHERE WHILE

/* Зарезервированные ключевые слова */
%token ABSTRACT BECOME BOX DO FINAL MACRO OVERRIDE PRIV TRY TYPEOF UNSIZED VIRTUAL YIELD

/* Идентификаторы и литералы */
%token ID RAW_IDENTIFIER
%token INTEGER_LITERAL_DEC INTEGER_LITERAL_BIN INTEGER_LITERAL_OCT INTEGER_LITERAL_HEX
%token FLOAT_LITERAL
%token STRING_LITERAL RAW_STRING_LITERAL
%token CHAR_LITERAL

/* Многосимвольные операторы (их нельзя записать как символьные литералы) */
%token RANGE_INCLUSIVE SHIFT_LEFT_ASSIGN SHIFT_RIGHT_ASSIGN NOT_EQUAL REMAINDER_ASSIGN 
%token LOGICAL_AND BIT_AND_ASSIGN MULTIPLY_ASSIGN PLUS_ASSIGN MINUS_ASSIGN RIGHT_ARROW 
%token RANGE DIVIDE_ASSIGN PATH_SEPARATOR SHIFT_LEFT LESS_EQUAL EQUAL_EQUAL FAT_ARROW 
%token GREATER_EQUAL SHIFT_RIGHT BIT_XOR_ASSIGN BIT_OR_ASSIGN LOGICAL_OR

/* ПРИОРИТЕТЫ И АССОЦИАТИВНОСТЬ */
%nonassoc BREAK RETURN
%nonassoc '{' '}'
%right ':'
%right '='
%nonassoc RANGE
%left LOGICAL_OR
%left LOGICAL_AND
%left '<' '>' EQUAL_EQUAL NOT_EQUAL LESS_EQUAL GREATER_EQUAL
%left '+' '-'
%left '*' '/' '%'
%left AS
%left '!' '&' UMINUS USTAR
%nonassoc '?'
%left '.' '['

%start Program

/* ПРАВИЛА ГРАММАТИКИ */

/* ---------------------- PROGRAM --------------------------- */
Program: ItemListEmpty 
       ;

/* ---------------------- VISIBILITY ------------------------- */
Visibility: PUB 
          | PUB '(' SUPER ')' 
          | PUB '(' SELF_VALUE ')' 
          ;

/* ---------------------- ITEMS ----------------------------- */
ItemListEmpty: /* empty */ 
             | ItemList 
             ;

ItemList: Item 
        | ItemList Item 
        ;

Item: SimpleItem 
    | Visibility SimpleItem 
    ;

SimpleItem: FuncStmt 
          | StructStmt 
          | EnumStmt 
          | ImplStmt 
          | TraitStmt 
          | ConstStmt 
          | ModuleStmt 
          ;

/* ---------------------- FUNCTIONS ------------------------- */
FuncStmt: DecFuncStmt 
        | ImplFuncStmt 
        ;

DecFuncStmt: FN ID '(' FuncParamListEmpty ')' ';' 
           | FN ID '(' FuncParamListEmpty ')' RIGHT_ARROW Type ';' 
           | FN ID '(' FuncParamListEmpty ')' RIGHT_ARROW IMPL Type ';' 
           ;

ImplFuncStmt: FN ID '(' FuncParamListEmpty ')' BlockExpr 
            | FN ID '(' FuncParamListEmpty ')' RIGHT_ARROW Type BlockExpr 
            | FN ID '(' FuncParamListEmpty ')' RIGHT_ARROW IMPL Type BlockExpr 
            ;

FuncParamListEmpty: /* empty */ 
                  | FuncParamList 
                  ;

FuncParamList: SELF_VALUE 
             | '&' SELF_VALUE 
             | '&' MUT SELF_VALUE 
             | FuncParam 
             | FuncParamList ',' FuncParam 
             ;

FuncParam: ID ':' Type 
         | ID ':' IMPL Type 
         | MUT ID ':' Type 
         | MUT ID ':' IMPL Type 
         | ID ':' '&' MUT Type 
         | ID ':' '&' MUT IMPL Type 
         | ID ':' '&' Type 
         | ID ':' '&' IMPL Type 
         ;

/* ---------------------- STRUCTS --------------------------- */
StructStmt: StructStruct 
          | TupleStruct 
          ;

StructStruct: STRUCT ID '{' StructFieldListEmpty '}' 
            | STRUCT ID ';' 
            ;

StructFieldListEmpty: /* empty */ 
                    | StructFieldList 
                    | StructFieldList ',' 
                    ;

StructFieldList: StructField 
               | StructFieldList ',' StructField 
               ;

StructField: ID ':' Type 
           | Visibility ID ':' Type 
           ;

TupleStruct: STRUCT ID '(' TupleFieldListEmpty ')' 
           ;

TupleFieldListEmpty: /* empty */ 
                   | TupleFieldList 
                   | TupleFieldList ',' 
                   ;

TupleFieldList: Type 
              | Visibility Type 
              | TupleFieldList ',' Type 
              | TupleFieldList ',' Visibility Type 
              ;

/* ---------------------- ENUMS ----------------------------- */
EnumStmt: ENUM ID '{' EnumItemListEmpty '}' 
        ;

EnumItemListEmpty: /* empty */ 
                 | ',' 
                 | EnumItemList 
                 | EnumItemList ',' 
                 ;

EnumItemList: EnumItem 
            | EnumItemList ',' EnumItem 
            ;

EnumItem: ID 
        | Visibility ID 
        | ID '=' ExprWithBlock 
        | ID '=' ExprWithoutBlock 
        | Visibility ID '=' ExprWithBlock 
        | Visibility ID '=' ExprWithoutBlock 
        | Visibility ID '{' StructFieldListEmpty '}' 
        | ID '{' StructFieldListEmpty '}' 
        ;

/* ---------------------- IMPL & TRAIT ---------------------- */
ImplStmt: IMPL Type '{' AssociatedItemListEmpty '}' 
        | IMPL Type FOR Type '{' AssociatedItemListEmpty '}' 
        ;

AssociatedItemListEmpty: /* empty */ 
                       | AssociatedItemList 
                       ;

AssociatedItemList: AssociatedItem 
                  | AssociatedItemList AssociatedItem 
                  ;

AssociatedItem: FuncStmt 
              | ConstStmt 
              | Visibility FuncStmt 
              | Visibility ConstStmt 
              ;

TraitStmt: TRAIT ID '{' AssociatedItemListEmpty '}' 
         | TRAIT ID ':' ID '{' AssociatedItemListEmpty '}' 
         ;

/* ---------------------- CONST & MODULE -------------------- */
ConstStmt: CONST ID ':' Type '=' ExprWithBlock ';' 
         | CONST ID ':' Type '=' ExprWithoutBlock ';' 
         | CONST ID ':' Type ';' 
         ;

ModuleStmt: MOD ID '{' ItemListEmpty '}' 
          ;

/* ---------------------- LET STATEMENT --------------------- */
LetStmt: LET ID '=' ExprWithBlock ';' 
       | LET ID '=' ExprWithoutBlock ';' 
       | LET ID ':' Type '=' ExprWithBlock ';' 
       | LET ID ':' Type '=' ExprWithoutBlock ';' 
       | LET MUT ID ';' 
       | LET MUT ID ':' Type ';' 
       | LET MUT ID '=' ExprWithBlock ';' 
       | LET MUT ID '=' ExprWithoutBlock ';' 
       | LET MUT ID ':' Type '=' ExprWithBlock ';' 
       | LET MUT ID ':' Type '=' ExprWithoutBlock ';' 
       ;

/* ---------------------- STATEMENTS ------------------------ */
StmtList: Stmt 
        | StmtList Stmt 
        ;

Stmt: ';' 
    | LetStmt 
    | ExprStmt 
    | ConstStmt 
    ;

ExprStmt: ExprWithoutBlock ';' 
        | ExprWithBlock 
        ;

/* ---------------------- EXPRESSIONS ----------------------- */
Expr: ExprWithoutBlock 
    | ExprWithBlock 
    ;

ExprWithoutBlock: CHAR_LITERAL 
                | STRING_LITERAL 
                | RAW_STRING_LITERAL 
                | INTEGER_LITERAL_DEC 
                | INTEGER_LITERAL_BIN 
                | INTEGER_LITERAL_OCT 
                | INTEGER_LITERAL_HEX 
                | FLOAT_LITERAL 
                | TRUE 
                | FALSE 
                | PathCallExpr 
                | Expr '.' ID 
                | Expr '.' INTEGER_LITERAL_DEC 
                | Expr '[' Expr ']' 
                | '[' ExprListEmpty ']' 
                | '[' Expr ';' Expr ']' 
                | CONTINUE 
                | BREAK 
                | BREAK Expr 
                | RANGE 
                | RANGE Expr 
                | Expr RANGE 
                | Expr RANGE Expr 
                | RETURN 
                | RETURN Expr 
                | '!' Expr %prec '!'
                | '*' Expr %prec USTAR
                | '&' Expr 
                | '&' MUT Expr 
                | '-' Expr %prec UMINUS
                | Expr '?' 
                | Expr AS Type 
                | Expr '+' Expr 
                | Expr '-' Expr 
                | Expr '*' Expr 
                | Expr '/' Expr 
                | Expr '%' Expr 
                | Expr LOGICAL_AND Expr 
                | Expr LOGICAL_OR Expr 
                | Expr '=' Expr 
                | Expr EQUAL_EQUAL Expr 
                | Expr NOT_EQUAL Expr 
                | Expr '>' Expr 
                | Expr '<' Expr 
                | Expr GREATER_EQUAL Expr 
                | Expr LESS_EQUAL Expr 
                ;

ExprWithBlock: BlockExpr 
             | LoopExpr 
             | IfExpr 
             ;

PathCallExpr: ID 
            | SUPER 
            | SELF_VALUE 
            | CRATE 
            | RAW_IDENTIFIER
            | PathCallExpr PATH_SEPARATOR ID 
            | PathCallExpr '(' ExprListEmpty ')' 
            ;

ExprListEmpty: /* empty */ 
             | ExprList 
             | ExprList ',' 
             ;

ExprList: Expr 
        | ExprList ',' Expr 
        ;

/* ---------------------- BLOCKS & CONTROL FLOW ------------- */
BlockExpr: '{' StmtList '}' 
         | '{' ExprWithoutBlock '}' 
         | '{' StmtList ExprWithoutBlock '}' 
         | '{' '}' 
         ;

LoopExpr: InfiniteLoopExpr 
        | PredicateLoopExpr 
        | IteratorLoopExpr 
        ;

InfiniteLoopExpr: LOOP BlockExpr 
                ;

PredicateLoopExpr: WHILE ExprWithBlock BlockExpr 
                 | WHILE ExprWithoutBlock BlockExpr 
                 ;

IteratorLoopExpr: FOR ID IN ExprWithBlock BlockExpr 
                | FOR ID IN ExprWithoutBlock BlockExpr 
                ;

IfExpr: SimpleIfElseExpr 
      | SimpleIfElseExpr ELSE BlockExpr 
      ;

SimpleIfElseExpr: SimpleIfExpr  
                | SimpleIfElseExpr ELSE SimpleIfExpr 
                ;

SimpleIfExpr: IF ExprWithoutBlock BlockExpr 
            | IF ExprWithBlock BlockExpr 
            ;

/* ---------------------- TYPES ----------------------------- */
Type: ID 
    | PathCallExpr 
    | '[' Type ';' Expr ']' 
    ;

/* ---------------------- STRUCT EXPRESSIONS ---------------- */
StructExprFieldList:  StructExprField 
                    | ',' StructExprField 
                    | StructExprFieldList ',' StructExprField 
                    ;

StructExprField: ID ':' ExprWithoutBlock  
               | ID ':' ExprWithBlock   
               ;