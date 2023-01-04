#include "Unit.h"

void Unit::insertFunc(Function *f)
{
    func_list.push_back(f);
}

void Unit::insertDecl(IdentifierSymbolEntry *se)
{
    decl_list.insert(se);
}

void Unit::removeFunc(Function *func)
{
    func_list.erase(std::find(func_list.begin(), func_list.end(), func));
}

void Unit::output() const
{
    for (auto item : decl_list)
        if (!item->not_dec_but_exist())
            item->decl_code();
    for (auto item : decl_list)
        if (item->not_dec_but_exist())
            item->decl_code();
    for (auto func : func_list)
        func->output();
}

Unit::~Unit()
{
    auto delete_list = func_list;
    for (auto &func : delete_list)
        delete func;
}
