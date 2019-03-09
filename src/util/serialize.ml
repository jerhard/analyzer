open Prelude
open GobConfig
open Analyses

let base_dir () = get_string "incremental.basedir"

let goblint_dirname = ".gob"

let versionMapFilename = "version.data"

let cilFileName = "ast.data"

let src_direcotry src_files =  let firstFile = List.first src_files in
                               Filename.dirname firstFile

let gob_directory src_files = let src_dir = src_direcotry src_files in
                              Filename.concat src_dir goblint_dirname


let current_commit src_files =
                        Git.current_commit (src_direcotry src_files) (* TODO: change to file path of analyzed src *)

let commit_dir src_files commit = 
  let gob_dir = gob_directory src_files in
  Filename.concat gob_dir commit

let current_commit_dir src_files = match current_commit src_files with 
    | Some commit -> (
      try
        let gob_dir = gob_directory src_files in
        let _path  = Goblintutil.create_dir gob_dir in
        let dir = Filename.concat gob_dir commit in
        Some (Goblintutil.create_dir dir)
      with e -> let error_message = (Printexc.to_string e) in
                print_newline ();
                print_string "The following error occured while creating a directory: " ;
                print_endline error_message;
                None)
    | None -> None (* git-directory not clean *)

(** A list of commits previously analyzed for the given src directory *)
let get_analyzed_commits src_files = 
  let src_dir = gob_directory src_files in
  Sys.readdir src_dir

let last_analyzed_commit src_files =
  try
    let src_dir = src_direcotry src_files in
    let commits = Git.git_log src_dir in
    let commitList = String.split_on_char '\n' commits in 
    let analyzed = get_analyzed_commits src_files in
    let analyzed_set = Set.of_array analyzed in
    Some (List.hd @@ List.drop_while (fun el -> not @@ Set.mem el analyzed_set) commitList)
  with e -> None

let marshall obj fileName  =
  let objString = Marshal.to_string obj [] in
  let file = File.open_out fileName in
  Printf.fprintf file "%s" objString;
  flush file;
  close_out file;;

let unmarshall fileName =
  let marshalled = input_file fileName in
  Marshal.from_string marshalled 0

let save_cil (file: Cil.file) (fileList: string list)= match current_commit_dir fileList with
  |Some dir ->
    let cilFile = Filename.concat dir cilFileName in
    marshall file cilFile
  | None -> print_endline "Failure when saving cil: working directory is dirty"
 
let loadCil (fileList: string list) = 
  (* TODO: Use the previous commit, or more specifally, the last analyzed commit *)
  match current_commit_dir fileList with
  |Some dir ->
    let cilFile = Filename.concat dir cilFileName in
    unmarshall cilFile
  | None -> None

let results_exist (src_files: string list) =
  last_analyzed_commit src_files <> None

let last_analyzed_commit_dir (src_files: string list) =
  match last_analyzed_commit src_files with
    | Some commit -> commit_dir src_files commit
    | None -> raise (Failure "No previous analysis results")

let load_latest_cil (src_files: string list) = 
  try
    let dir = last_analyzed_commit_dir src_files  in
    let cil = Filename.concat dir cilFileName in
    Some (unmarshall cil)
  with e -> None