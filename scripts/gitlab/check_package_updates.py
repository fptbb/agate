import os
import yaml
import subprocess
import time
import shutil

def is_root():
    return os.geteuid() == 0

def run_cmd(cmd, use_sudo=False, capture=True):
    if use_sudo and not is_root():
        cmd = ['sudo'] + cmd
    
    if capture:
        return subprocess.run(cmd, capture_output=True, text=True, check=True)
    return subprocess.run(cmd, check=True)

def extract_data(data, packages, coprs, repo_files):
    if isinstance(data, dict):
        module_type = data.get('type')
        if module_type in ['rpm-ostree', 'dnf']:
            repos = data.get('repos', {})
            if isinstance(repos, dict):
                for copr in repos.get('copr', []):
                    coprs.add(copr)
                for repo_file in repos.get('files', []):
                    repo_files.add(repo_file)
            
            install_data = data.get('install', [])
            pkg_list = []
            
            if isinstance(install_data, dict):
                pkg_list = install_data.get('packages', [])
            elif isinstance(install_data, list):
                pkg_list = install_data
                
            for pkg in pkg_list:
                packages.add(pkg)
                
        elif 'modules' in data:
            extract_data(data['modules'], packages, coprs, repo_files)
            
    elif isinstance(data, list):
        for item in data:
            extract_data(item, packages, coprs, repo_files)

def get_data_from_directories(directories):
    packages = set()
    coprs = set()
    repo_files = set()
    
    for directory in directories:
        if not os.path.exists(directory):
            continue
        
        for root, _, files in os.walk(directory):
            for file in files:
                if file.endswith('.yml') or file.endswith('.yaml'):
                    filepath = os.path.join(root, file)
                    with open(filepath, 'r') as f:
                        try:
                            data = yaml.safe_load(f)
                            extract_data(data, packages, coprs, repo_files)
                        except yaml.YAMLError:
                            continue
                            
    return list(packages), list(coprs), list(repo_files)

def enable_coprs(coprs):
    if not coprs:
        return
    print(f"Enabling {len(coprs)} COPR repositories...")
    for copr in coprs:
        cmd = ['dnf', 'copr', 'enable', '-y', copr]
        try:
            run_cmd(cmd, use_sudo=True, capture=False)
        except subprocess.CalledProcessError:
            pass

def setup_repo_files(repo_files):
    if not repo_files:
        return
    print(f"Setting up {len(repo_files)} custom repository files...")
    system_repo_dir = "/etc/yum.repos.d/"
    for repo_file in repo_files:
        for root, _, files in os.walk('.'):
            if repo_file in files:
                src_path = os.path.join(root, repo_file)
                dest_path = os.path.join(system_repo_dir, repo_file)
                try:
                    if not is_root():
                        run_cmd(['cp', src_path, dest_path], use_sudo=True, capture=False)
                    else:
                        shutil.copy(src_path, dest_path)
                    break
                except Exception:
                    break

def check_for_recent_updates(packages):
    if not packages:
        return False

    print("\nRefreshing dnf cache...")
    try:
        run_cmd(['dnf', 'makecache', '-y'], use_sudo=True, capture=False)
    except subprocess.CalledProcessError:
        print("Failed to refresh dnf cache.")

    print(f"Querying {len(packages)} packages from repositories...")
    
    cmd = ['dnf', '-y', '-q', 'repoquery', '--latest-limit=1', '--qf', '%{name}|%{buildtime}\n'] + packages
    
    try:
        result = run_cmd(cmd)
    except subprocess.CalledProcessError:
        print("Query failed.")
        return False

    one_day_ago = time.time() - 86400
    pkg_buildtimes = {}

    for line in result.stdout.strip().split('\n'):
        if '|' in line:
            name, btime_str = line.split('|', 1)
            if btime_str.isdigit():
                btime = int(btime_str)
                if name not in pkg_buildtimes or btime > pkg_buildtimes[name]:
                    pkg_buildtimes[name] = btime

    updates_found = []
    up_to_date = []

    for name, btime in pkg_buildtimes.items():
        if btime >= one_day_ago:
            updates_found.append(name)
        else:
            up_to_date.append(name)

    print("\n--- Summary ---")
    print(f"Total requested: {len(packages)}")
    print(f"Total resolved:  {len(pkg_buildtimes)}")
    print(f"Updates found:   {len(updates_found)}")
    print(f"Up to date:      {len(up_to_date)}")
    
    if updates_found:
        print(f"\nPackages with updates: {', '.join(updates_found)}")

    return len(updates_found) > 0

if __name__ == "__main__":
    packages, coprs, repo_files = get_data_from_directories(['recipes', 'modules'])

    enable_coprs(coprs)
    setup_repo_files(repo_files)

    if packages:
        if check_for_recent_updates(packages):
            print("\nWriting FORCE_BUILD to build.env")
            with open('build.env', 'a') as f:
                f.write('FORCE_BUILD="true"\n')
        else:
            print("\nNo updates required. Env file not created.")
    else:
        print("Failed to extract any packages from the parsed files.")