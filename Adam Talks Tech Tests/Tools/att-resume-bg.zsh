#!/bin/zsh
# Wakes macOS's Photos/Spotlight scanners if a test was force-quit while they were paused.
for p in mediaanalysisd photoanalysisd photolibraryd cloudphotod corespotlightd mdworker_shared mdworker textunderstandingd duetexpertd suggestd knowledgeconstructiond searchpartyd; do
  pkill -CONT -x -U $UID "$p" 2>/dev/null
done
for p in mds mds_stores kernelmanager_helper XprotectService; do sudo -n pkill -CONT -x $p 2>/dev/null || sudo pkill -CONT -x $p 2>/dev/null; done
sudo -n pkill -CONT -f XProtectRemediator 2>/dev/null
print "Photos/Spotlight scanning resumed."
