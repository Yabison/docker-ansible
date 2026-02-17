#/bin/bash
PATH_DIR='/home/devops/.ansible/roles-git'
submodules=`cat /home/devops/.requirements_git.yml | grep src  |  cut -d ':' -f2-   | tr -d '"' | tr -d "'" | tr -d '\n'`
echo "Add modules/roles in ${PATH_DIR}"
for module in $submodules ; do
	name=`basename $module`
	echo  "${name%.*}"  
	if [ ! -d "${PATH_DIR}/${name%.*}" ]; then
    echo "git clone $module ${PATH_DIR}/${name%.*}"
		git clone $module ${PATH_DIR}/${name%.*}
	else
		echo "skip (already installed)"
	fi
done
