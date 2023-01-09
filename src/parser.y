%code top{
    #include <iostream>
    #include <assert.h>
    #include "parser.h"
    extern Ast ast;
    int yylex();
    int yyerror( char const *);
    Type *curType = nullptr;
    Type *retType = nullptr;
    bool inWhileBlock = false;
    bool needRet = false;
}

%code requires {
    #include "Ast.h"
    #include "SymbolTable.h"
    #include "Type.h"
}

%union {
    int itype;
    float ftype;
    char *strtype;
    StmtNode *stmttype;
    ExprNode *exprtype; 
    Type *type;
}


%start CompUnit
%token INT FLOAT CONST VOID IF WHILE RETURN ELSE BREAK CONTINUE
%token <strtype> ID 
%token ADD SUB MUL DIV MOD
%token OR AND 
%token ASSIGN
%token EQ NEQ LESS LESSEQ GREATER GREATEREQ
%token NOT
%token <itype> INTEGERCONST
%token <ftype> FLOATCONST
%token COMMA SEMICOLON LPAREN RPAREN LBRACE RBRACE LBRACKET RBRACKET


%nterm <stmttype> Stmts Stmt AssignStmt ExprStmt BlockStmt NullStmt IfStmt WhileStmt BreakStmt ContinueStmt ReturnStmt DeclStmt 
%nterm <stmttype> VarDeclStmt ConstDeclStmt VarDef ConstDef VarDefList ConstDefList
%nterm <stmttype> FuncFParams FuncRParams FuncDef 
%nterm <exprtype> LVal Exp ConstExp Cond PrimaryExpr UnaryExpr MulDivModExpr AddSubExpr RelExpr LEqExpr LAndExpr LOrExpr 
%nterm <stmttype> InitVal ConstInitVal InitValList ConstInitValList 
%nterm <exprtype> FuncFParam
%nterm <type> Type 

%precedence THEN
%precedence ELSE
%%
CompUnit
    : Stmts {
        ast.setRoot($1);
        // 未检查main函数的存在
    }
    ;
Stmts
    : Stmt {$$ = new SeqStmt($1);}
    | Stmts Stmt{
        ((SeqStmt*)$1)->addChild($2);
        $$ = $1;
    }
    ;
Stmt
    : AssignStmt {$$=$1;}
    | ExprStmt {$$=$1;}
    | BlockStmt {$$=$1;}
    | NullStmt {$$=$1;}
    | IfStmt {$$=$1;}
    | WhileStmt {$$=$1;}
    | BreakStmt {$$=$1;}
    | ContinueStmt {$$=$1;}
    | ReturnStmt {$$=$1;}
    | DeclStmt {$$=$1;}
    | FuncDef {$$=$1;}
    ;
Type
    : INT {
        $$ = curType = TypeSystem::intType;
    }
    | FLOAT {
        $$ = curType = TypeSystem::floatType;
    }
    | VOID {
        $$ = curType = TypeSystem::voidType;
    }
    // 需要额外检查，比如 VOID 不能出现在声明语句。
    ;
// ArrayConstIndices
//     : ArrayConstIndices LBRACKET ConstExp RBRACKET {
//         IndicesNode* node = dynamic_cast<IndicesNode*>($1);
//         node->Addnew($3);
//         $$ = node;
//     }
//     | LBRACKET ConstExp RBRACKET {
//         IndicesNode* node = new IndicesNode();
//         node->Addnew($2);
//         $$ = node;
//     }
//     ;
// ArrayVarIndices
//     : ArrayVarIndices LBRACKET Exp RBRACKET {
//         IndicesNode* node = dynamic_cast<IndicesNode*>($1);
//         node->Addnew($3);
//         $$ = node;
//     }
//     | LBRACKET Exp RBRACKET {
//         IndicesNode* node = new IndicesNode();
//         node->Addnew($2);
//         $$ = node;
//     }
//     ;
// ArrayIndices
//     : ArrayConstIndices {
//         $$ = $1;
//     }
//     | ArrayVarIndices {
//         $$ = $1;
//     }
//     ;
LVal
    : ID {
        SymbolEntry *se;
        se = identifiers->lookup($1);
        // 类型检查1：变量未声明
        if(se == nullptr)
        {
            fprintf(stderr, "identifier \"%s\" is undefined\n", (char*)$1);
            delete [](char*)$1;
            assert(se != nullptr);
        }
        $$ = new Id(se);
        delete []$1;
    }
    // | ID ArrayIndices {
    //     SymbolEntry *se;
    //     se = identifiers->lookup($1);
    //     // 类型检查1：变量未声明
    //     if(se == nullptr)
    //     {
    //         fprintf(stderr, "identifier \"%s\" is undefined\n", (char*)$1);
    //         delete [](char*)$1;
    //         assert(se != nullptr);
    //     }
    //     Id* new_id = new Id(se);
    //     new_Id->SetIndices(dynamic_cast<IndicesNode*>($2));
    //     $$ = new_id;
    //     delete []$1;
    // }
    // ; 

Exp
    :
    AddSubExpr {$$ = $1;}
    ;
ConstExp
    : 
    AddSubExpr {
        assert($1->getType()->isConst()); // to do：考虑数组类型
        $$ = $1;
    }
    ;
Cond
    :
    LOrExpr {
        $$ = typeCast($1, logicMax($1->getType(), $1->getType()));
    }
    ;
FuncRParams 
    : Exp {
        FuncCallParamsNode *node = new FuncCallParamsNode();
        node->addChild($1);
        $$ = node;
    }
    | FuncRParams COMMA Exp {
        FuncCallParamsNode *node = dynamic_cast<FuncCallParamsNode*>($1);
        node->addChild($3);
        $$ = node;
    }
    | %empty {
       $$ = nullptr;
    }
    ;
PrimaryExpr
    : LPAREN Exp RPAREN {
        $$ = $2;
    }
    | LVal {
        $$ = $1;
    }
    | INTEGERCONST {
        SymbolEntry *se = new ConstantSymbolEntry(TypeSystem::constIntType, $1);
        $$ = new Constant(se);
    }
    | FLOATCONST {
        SymbolEntry *se = new ConstantSymbolEntry(TypeSystem::constFloatType, $1);
        $$ = new Constant(se);
    }
    ;
UnaryExpr 
    : PrimaryExpr {$$ = $1;}
    | ID LPAREN FuncRParams RPAREN {
        std::vector<Type *> paramsType =  ($3 != nullptr) ? ((FuncCallParamsNode*)$3)->getParamsType() : std::vector<Type *>{};
        SymbolEntry *se = identifiers->lookup($1, true, paramsType);
        // 类型检查4、5：函数未声明+参数不匹配
        if(se == nullptr)
        {
            fprintf(stderr, "function \"%s\" is undefined or params mismatch\n", (char*)$1);
            delete [](char*)$1;
            assert(se != nullptr);
        }
        //实参类型隐式转化
        if($3 != nullptr)
        {
            std::vector<ExprNode *> RParams = dynamic_cast<FuncCallParamsNode *>$3->getParams();
            std::vector<Type *> FParamsType = dynamic_cast<FunctionType *>(se->getType())->getParamsType();
            for(size_t i = 0; i != RParams.size(); i++)
                RParams[i] = typeCast(RParams[i], FParamsType[i]);
            dynamic_cast<FuncCallParamsNode *>$3->setParams(RParams);
        }
        Type *retType = dynamic_cast<FunctionType *>(se->getType())->getRetType();
        SymbolEntry *t = new TemporarySymbolEntry(retType, SymbolTable::getLabel()); // 1.函数调用没做常量传播 2.某些函数调用无需返回值，但这里也分配了一个临时符号
        $$ = new FuncCallNode(t, new Id(se), (FuncCallParamsNode*)$3);
    }
    | ADD UnaryExpr {
        $$ = $2;
    }
    | SUB UnaryExpr {
        Type *resType = unaryMax($2->getType(), TypeSystem::MINUS);
        ExprNode *t = typeCast($2, resType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, -(t->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new UnaryExpr(se, UnaryExpr::MINUS, t);
    }
    | NOT UnaryExpr {
        Type *resType = unaryMax($2->getType(), TypeSystem::NOT);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, !($2->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new UnaryExpr(se, UnaryExpr::NOT, $2);
    }// 需要额外检查，'!'不能出现在算数表达式中
    ;
MulDivModExpr
    : UnaryExpr {
        $$ = $1;
        // $$->setType(calcMax($1->getType(), $1->getType()));
    }
    | MulDivModExpr MUL UnaryExpr {
        Type *resType = calcMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, resType), *t3 = typeCast($3, resType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) * (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::MUL, t1, t3);
    }
    | MulDivModExpr DIV UnaryExpr {
        Type *resType = calcMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, resType), *t3 = typeCast($3, resType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) / (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::DIV, t1, t3);
    }
    | MulDivModExpr MOD UnaryExpr {
        // 类型检查3：非整数类型参与取模运算
        if(!($1->getType()->isInt() && $3->getType()->isInt()))
        {
            fprintf(stderr, "%s mod %s\n", $1->getType()->toStr().c_str(), $3->getType()->toStr().c_str());
            assert($1->getType()->isInt() && $3->getType()->isInt());
        }
        Type *resType = calcMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, resType), *t3 = typeCast($3, resType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (int)(t1->getValue()) % (int)(t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::MOD, t1, t3);
    }
    ;
AddSubExpr
    : MulDivModExpr {$$ = $1;}
    | AddSubExpr ADD MulDivModExpr {
        Type *resType = calcMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, resType), *t3 = typeCast($3, resType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) + (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::ADD, t1, t3);
    }
    | AddSubExpr SUB MulDivModExpr {
        Type *resType = calcMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, resType), *t3 = typeCast($3, resType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) - (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::SUB, t1, t3);
    }
    ;
RelExpr
    : AddSubExpr {
        $$ = $1;
    }
    | RelExpr LESS AddSubExpr {
        Type *maxType = relMax($1->getType(), $3->getType()), *resType = logicMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, maxType), *t3 = typeCast($3, maxType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) < (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::LESS, t1, t3);
    }
    | RelExpr LESSEQ AddSubExpr {
        Type *maxType = relMax($1->getType(), $3->getType()), *resType = logicMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, maxType), *t3 = typeCast($3, maxType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) <= (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::LESSEQ, t1, t3);
    }
    | RelExpr GREATER AddSubExpr {
        Type *maxType = relMax($1->getType(), $3->getType()), *resType = logicMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, maxType), *t3 = typeCast($3, maxType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) > (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::GREATER, t1, t3);
    }
    | RelExpr GREATEREQ AddSubExpr {
        Type *maxType = relMax($1->getType(), $3->getType()), *resType = logicMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, maxType), *t3 = typeCast($3, maxType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) >= (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::GREATEREQ, t1, t3);
    }
    ;
LEqExpr
    : RelExpr {$$ = $1;}
    | LEqExpr EQ RelExpr {
        Type *maxType = relMax($1->getType(), $3->getType()), *resType = logicMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, maxType), *t3 = typeCast($3, maxType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) == (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::EQ, t1, t3);
    }
    | LEqExpr NEQ RelExpr {
        Type *maxType = relMax($1->getType(), $3->getType()), *resType = logicMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, maxType), *t3 = typeCast($3, maxType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) != (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::NEQ, t1, t3);
    }
    ;
LAndExpr
    : LEqExpr {$$ = $1;}
    | LAndExpr AND LEqExpr {
        Type *resType = logicMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, resType), *t3 = typeCast($3, resType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) && (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::AND, t1, t3);
    }
    ;
LOrExpr
    : LAndExpr {$$ = $1;}
    | LOrExpr OR LAndExpr {
        Type *resType = logicMax($1->getType(), $3->getType());
        ExprNode *t1 = typeCast($1, resType), *t3 = typeCast($3, resType);
        SymbolEntry *se;
        if(resType->isConst()) // 常量传播
            se = new ConstantSymbolEntry(resType, (t1->getValue()) || (t3->getValue()));
        else
            se = new TemporarySymbolEntry(resType, SymbolTable::getLabel());
        $$ = new BinaryExpr(se, BinaryExpr::OR, t1, t3);
    }
    ;
AssignStmt
    : LVal ASSIGN Exp SEMICOLON { // SysY不包含连续赋值的特性
        assert(convertible($3->getType(), $1->getType()));
        ExprNode *t = typeCast($3, $1->getType());
        if($1->getType()->isConst())
            $1->setValue(t->getValue()); // 常量定义后应该不会再赋值，这段话不会执行
        $$ = new AssignStmt($1, t); 
    }
    ;
ExprStmt
    : Exp SEMICOLON {
        $$ = new ExprStmt($1);
    }
    ;
BlockStmt
    : LBRACE {
        identifiers = new SymbolTable(identifiers);
    } 
    Stmts RBRACE {
        $$ = new CompoundStmt($3);
        SymbolTable *top = identifiers;
        identifiers = identifiers->getPrev();
        delete top;
    }
    | LBRACE RBRACE {
        $$ = new CompoundStmt(nullptr);
    }
    ;
NullStmt
    : SEMICOLON {
        $$ = new NullStmt();
    }
    ;
IfStmt
    // Stmt不为 BlockStmt 则符号表作用域未变，可能出现问题
    : IF LPAREN Cond RPAREN Stmt %prec THEN {
        $$ = new IfStmt($3, $5);
    }
    | IF LPAREN Cond RPAREN Stmt ELSE Stmt {
        $$ = new IfElseStmt($3, $5, $7);
    }
    ;
WhileStmt
    // Stmt不为 BlockStmt 则符号表作用域未变，可能出现问题
    : WHILE LPAREN Cond RPAREN {
        inWhileBlock = true;
    } Stmt {
        $$ = new WhileStmt($3, $6);
        inWhileBlock = false;
    }
    ;
BreakStmt
    : BREAK SEMICOLON {
        // 类型检查8：while-break
        if(!inWhileBlock)
        {
            fprintf(stderr, "\"break\" not in whilestmt\n");
            assert(inWhileBlock);
        }
        $$ = new BreakStmt();
    }
    ;
ContinueStmt
    : CONTINUE SEMICOLON {
        // 类型检查8：while-continue
        if(!inWhileBlock)
        {
            fprintf(stderr, "\"continue\" not in whilestmt\n");
            assert(inWhileBlock);
        }
        $$ = new ContinueStmt();
    }
    ;
ReturnStmt
    : RETURN SEMICOLON {
        // 类型检查6：return类型检查
        if(!retType->isVoid())
        {
            fprintf(stderr, "retType mismatch: return \"%s\", expected \"%s\"\n", TypeSystem::voidType->toStr().c_str(), retType->toStr().c_str());
            assert(retType->isVoid());
        }
        $$ = new ReturnStmt(nullptr);
        needRet = false;
    }
    | RETURN Exp SEMICOLON {
        // 类型检查6：return类型检查
        if(!convertible($2->getType(), retType))
        {
            fprintf(stderr, "retType mismatch: return \"%s\", expected \"%s\"\n", $2->getType()->toStr().c_str(), retType->toStr().c_str());
            assert(convertible($2->getType(), retType));
        }
        ExprNode *t = typeCast($2, retType);
        $$ = new ReturnStmt(t);
        needRet = false;
    }
    ;
DeclStmt
    : VarDeclStmt {$$ = $1;}
    | ConstDeclStmt {$$ = $1;}
    ;
VarDeclStmt
    : 
    Type VarDefList SEMICOLON {
        $$ = $2;
    }
    ;
ConstDeclStmt
    : CONST Type ConstDefList SEMICOLON {
        $$ = $3;
    }
    ;
VarDefList
    : VarDefList COMMA VarDef {
        ((DeclStmt*)$3)->setNext(((DeclStmt*)$1)->getNext());
        ((DeclStmt*)$1)->setNext((DeclStmt*)$3);
        $$ = $1;
    } 
    | VarDef {$$ = $1;}
    ;
ConstDefList
    : ConstDefList COMMA ConstDef {
        ((DeclStmt*)$3)->setNext(((DeclStmt*)$1)->getNext());
        ((DeclStmt*)$1)->setNext((DeclStmt*)$3);
        $$ = $1;
    }
    | ConstDef {$$ = $1;}
    ;
VarDef
    : ID {
        SymbolEntry *se = new IdentifierSymbolEntry(curType, $1, identifiers->getLevel());
        int ret = identifiers->install($1, se);
        // 类型检查1：变量在同一作用域下重复声明
        if(!ret)
        {
            fprintf(stderr, "identifier \"%s\" is redefined\n", (char*)$1);
            delete [](char*)$1;
            assert(ret);
        }
        $$ = new DeclStmt(new Id(se));
        delete []$1;
    }
    | ID ASSIGN InitVal {
        assert(convertible((dynamic_cast<InitNode*>($3))->getself()->getType(), curType));
        ExprNode *t3 = typeCast((dynamic_cast<InitNode*>($3))->getself(), curType);
        (dynamic_cast<InitNode*>($3))->setleaf(t3);
        SymbolEntry *se = new IdentifierSymbolEntry(curType, $1, identifiers->getLevel());
        int ret = identifiers->install($1, se);
        // 类型检查1：变量在同一作用域下重复声明
        if(!ret)
        {
            fprintf(stderr, "identifier \"%s\" is redefined\n", (char*)$1);
            delete [](char*)$1;
            assert(ret);
        }
        // 常量传播起点
        if((dynamic_cast<InitNode*>($3))->getself()->getType()->isConst())
            se->setValue((dynamic_cast<InitNode*>($3))->getself()->getValue());
        $$ = new DeclStmt(new Id(se), (dynamic_cast<InitNode*>($3)));
        delete []$1;
    }
    // | ID ArrayConstIndices {
    //     int ret = identifiers->lookup($1);
    //     // 类型检查1：变量在同一作用域下重复声明
    //     if(!ret)
    //     {
    //         fprintf(stderr, "identifier \"%s\" is redefined\n", (char*)$1);
    //         delete [](char*)$1;
    //         assert(ret);
    //     }
    //     Type* type = curType->isInt() ? new IntArrayType() : new FloatArrayType();
    //     SymbolEntry *se_var_list = new IdentifierSymbolEntry(type, $1, identifiers->getLevel());
    //     identifier->install($1, se_var_list);
    //     Id* new_Id = new Id(se);
    //     new_Id->SetIndices(dynamic_cast<IndicesNode*>($2));
    //     $$ = new DeclStmt(new_Id, nullptr, false, true);
    //     delete []$1;
    // }
    // | ID ArrayConstIndices ASSIGN InitVal {
    //     int ret = identifiers->lookup($1);
    //     // 类型检查1：变量在同一作用域下重复声明
    //     if(!ret)
    //     {
    //         fprintf(stderr, "identifier \"%s\" is redefined\n", (char*)$1);
    //         delete [](char*)$1;
    //         assert(ret);
    //     }
    //     Type* type = curType->isInt() ? new IntArrayType() : new FloatArrayType();
    //     SymbolEntry *se_var_list = new IdentifierSymbolEntry(type, $1, identifiers->getLevel());
    //     identifier->install($1, se_var_list);
    //     Id* new_Id = new Id(se);
    //     new_Id->SetIndices(dynamic_cast<IndicesNode*>($2));
    //     $$ = new DeclStmt(new_Id, dynamic_cast<InitNode*>($4), false, true);
    //     delete []$1;
    // }
    // | ID ArrayVarIndices ASSIGN InitVal {
    //     fprintf(stderr, "Indices can't be variable!\n");
    //     bool indices_variable = false;
    //     assert(indices_variable);
    // }
    // ;
ConstDef
    : ID ASSIGN ConstInitVal {
        curType = Var2Const(curType);
        assert(convertible((dynamic_cast<InitNode*>($3))->getself()->getType(), curType));
        ExprNode *t3 = typeCast((dynamic_cast<InitNode*>($3))->getself(), curType);
        SymbolEntry *se = new IdentifierSymbolEntry(curType, $1, identifiers->getLevel());
        // 常量传播起点
        se->setValue((dynamic_cast<InitNode*>($3))->getself()->getValue());
        int ret = identifiers->install($1, se);
        // 类型检查1：变量在同一作用域下重复声明
        if(!ret)
        {
            fprintf(stderr, "identifier \"%s\" is redefined\n", (char*)$1);
            delete [](char*)$1;
            assert(ret);
        }
        $$ = new DeclStmt(new Id(se), (dynamic_cast<InitNode*>($3)));
        delete []$1;
    }
    // | ID ArrayConstIndices ASSIGN ConstInitVal {
    //     int ret = identifiers->lookup($1);
    //     // 类型检查1：变量在同一作用域下重复声明
    //     if(!ret)
    //     {
    //         fprintf(stderr, "identifier \"%s\" is redefined\n", (char*)$1);
    //         delete [](char*)$1;
    //         assert(ret);
    //     }
    //     Type* type = curType->isInt() ? new IntArrayType() : new FloatArrayType();
    //     SymbolEntry *se_var_list = new IdentifierSymbolEntry(type, $1, identifiers->getLevel());
    //     identifier->install($1, se_var_list);
    //     Id* new_Id = new Id(se);
    //     new_Id->SetIndices(dynamic_cast<IndicesNode*>($2));
    //     $$ = new DeclStmt(new_Id, dynamic_cast<InitNode*>($4), true, true);
    //     delete []$1;
    // }
    // | ID ArrayVarIndices ASSIGN ConstInitVal {
    //     fprintf(stderr, "Indices can't be variable!\n");
    //     bool indices_variable = false;
    //     assert(indices_variable);
    // }
    ;
InitVal 
    : Exp {
        InitNode* new_exp = new InitNode(false);
        new_exp->setleaf(dynamic_cast<ExprNode*>($1));
        $$ = new_exp;
    }
    // 这样的大括号初始化方式太过灵活，需要额外检查
    | LBRACE InitValList RBRACE {
        $$ = $2;;
    }
    | LBRACE RBRACE {
        $$ = new InitNode(true);
    }
    ;

ConstInitVal
    : ConstExp {
        InitNode* new_exp = new InitNode(true);
        new_exp->setleaf(dynamic_cast<ExprNode*>($1));
        $$ = new_exp;
    }
    | LBRACE ConstInitValList RBRACE {
        $$ = $2;
    }
    | LBRACE RBRACE {
        $$ = new InitNode(true);
    }
    ;
InitValList
    : InitVal {
        InitNode* new_expr = new InitNode(false);
        new_expr->addleaf(dynamic_cast<InitNode*>($1));
        $$ = new_expr;
    }
    | InitValList COMMA InitVal {
        InitNode* this_expr = dynamic_cast<InitNode*>($1);
        this_expr->addleaf(dynamic_cast<InitNode*>($3));
        $$ = this_expr;
    }
    ;
ConstInitValList
    : ConstInitVal {
        InitNode* new_expr = new InitNode(true);
        new_expr->addleaf(dynamic_cast<InitNode*>($1));
        $$ = new_expr;
    }
    | ConstInitValList COMMA ConstInitVal {
        InitNode* this_expr = dynamic_cast<InitNode*>($1);
        this_expr->addleaf(dynamic_cast<InitNode*>($3));
        $$ = this_expr;
    }
    ;
FuncDef
    :
    Type ID {
        retType = $1;
        needRet = true;
        identifiers = new SymbolTable(identifiers);
    }
    LPAREN FuncFParams{
        Type *FuncType = ($5 != nullptr) ? new FunctionType($1, ((FuncDefParamsNode*)$5)->getParamsType()) : new FunctionType($1, {});
        SymbolEntry *se = new IdentifierSymbolEntry(FuncType, $2, identifiers->getLevel() - 1);
        int ret = identifiers->getPrev()->install($2, se);
        // 类型检查4：参数类型相同的函数重定义
        if(!ret)
        {
            fprintf(stderr, "function \"%s\" is redefined\n", (char*)$2);
            delete [](char*)$2;
            assert(ret);
        }
    }
    RPAREN BlockStmt{
        // 类型检查6：缺少return，比较粗略，某个分支没有return但其它分支有return的情况检查不出来
        if(needRet)
        {
            if($1->isVoid())
                ((SeqStmt*)(((CompoundStmt*)$8)->getStmt()))->addChild(new ReturnStmt(nullptr));
            else
            {
                fprintf(stderr, "missing return stmt\n");
                assert(!needRet);
            }
        }
        SymbolEntry *se =  ($5 != nullptr) ? identifiers->lookup($2, true, ((FuncDefParamsNode*)$5)->getParamsType()):identifiers->lookup($2, true, {});
        assert(se != nullptr);
        $$ = new FuncDefNode(se, dynamic_cast<FuncDefParamsNode*>($5), $8, needRet);
        SymbolTable *top = identifiers;
        identifiers = identifiers->getPrev();
        delete top;
        delete []$2;
    }
    ;
FuncFParams
    : FuncFParams COMMA FuncFParam {
       ((FuncDefParamsNode*)$1)->addChild((Id*)$3);
       $$ = $1;
    }
    | FuncFParam {
        $$ = new FuncDefParamsNode();
        ((FuncDefParamsNode*)$$)->addChild((Id*)$1);
    }
    | %empty {
        $$ = nullptr;
    }
    ;
FuncFParam
    : Type ID {
        SymbolEntry *se = new IdentifierSymbolEntry($1, $2, identifiers->getLevel());
        identifiers->install($2, se);
        $$ = new Id(se);
        delete []$2;
    }
    // | Type ID FuncArrayIndices
    ;
// FuncArrayIndices
//     // SysY官方文档里是Exp而不是ConstExp
//     : FuncFParamArrayIndices LBRACKET ConstExp RBRACKET {

//     }
//     | LBRACKET RBRACKET {

//     }
//     ;
%%

int yyerror(char const *message)
{
    std::cerr<<message<<std::endl;
    return -1;
}
