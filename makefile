parser: y.tab.c lex.yy.c
	gcc -o parser y.tab.c lex.yy.c

y.tab.c y.tab.h: B11033015.y
	yacc -d B11033015.y

lex.yy.c: B11033015.l y.tab.h
	flex B11033015.l

clean:
	rm -f parser.exe y.tab.c y.tab.h lex.yy.c