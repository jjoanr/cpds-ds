# Makefile for cpds-ds Paxy assignment
MAIN = paxy-report

all:
	latexmk -pdf $(MAIN).tex

clean:
	latexmk -c

clean-all:
	latexmk -C

rebuild: clean-all all

.PHONY: all clean clean-all rebuild
