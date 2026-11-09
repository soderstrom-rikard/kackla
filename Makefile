WOW_INTERFACE_DIR=/tmp/WoW/Interface/Addons

-include personal.mak

KACKLA_DIR=${WOW_INTERFACE_DIR}/kackla

all: *.lua *.toc *.xml *.tga
	mkdir -p ${KACKLA_DIR}
	cp $? ${KACKLA_DIR}
	rm ${KACKLA_DIR}/*.test.lua

clean:
	rm -rf ${KACKLA_DIR}
