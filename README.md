# nifi-configurator

Add a secondary disk to be used to store
- container images
- container data for nifi
- ssl certificates

make sure that zfts and sarzip are installed, or the pod will not start as it maps out some files they use from the host.

after that..

login as username "admin" (ssh or locally)
run Install_Menu.sh

set values in option 0 first,
then run through the steps in order
for the image step, only pick 7 or 8, not both, unless your online.
choosing both will not hurt, but basicaly option 8 will overwrite what option 7 does, so why do both?

If you need to edit the yml data for the pod, edit the template in nifi-pod/nifi-pod.yml.template and rerun the steps, or just step 9 in most cases will regenerate the pod.
