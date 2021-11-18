SHELL=/bin/bash
.PHONY: list
list:
	@sh -c "$(MAKE) -p no_targets__ 2>/dev/null | \
		awk -F':' '/^[a-zA-Z0-9][^\$$#\/\\t=]*:([^=]|$$)/ {split(\$$1,A,/ /);for(i in A)print A[i]}' | \
		grep -v Makefile | \
		grep -v '%' | \
		grep -v '__\$$' | \
		sort -u"

markdown:
	for each_file in *.erb ; do ln -sf $${each_file} $${each_file/.erb/}; done

mdtohtml:
	go get -u github.com/gomarkdown/mdtohtml

html:
	for each_file in *.erb ; do mdtohtml $${each_file} > $${each_file/.md.erb/}; done

clean:
	git clean -dxf .
