// Read-only reconstruction of installed CortexService's V1 file-key retriever.
// Derived keys are kept in memory and never printed. Originals are not modified.
#include <arrow/api.h>
#include <arrow/io/api.h>
#include <parquet/arrow/reader.h>
#include <parquet/arrow/writer.h>
#include <parquet/encryption/encryption.h>
#include <CommonCrypto/CommonDigest.h>
#include <iostream>
#include <filesystem>
class Retriever: public parquet::DecryptionKeyRetriever {
 std::string GetKey(const std::string& metadata) override {
  auto a=metadata.find(':');auto b=metadata.find(':',a==std::string::npos?0:a+1);
  if(a==std::string::npos||b==std::string::npos||metadata.substr(0,a)!="1"||metadata.find(':',b+1)!=std::string::npos)throw std::runtime_error("Unsupported key metadata");
  std::string material=std::string("emotiv_jan2019")+metadata.substr(a+1,b-a-1)+metadata.substr(b+1);
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(material.data(),(CC_LONG)material.size(),digest);
  return std::string((char*)digest,sizeof(digest));
 }
};
void check(arrow::Status status){if(!status.ok())throw std::runtime_error(status.ToString());}
int main(int argc,char**argv){try{
 if(argc!=3 && argc!=4)throw std::runtime_error("Usage: read_record input.eparquet new-output.parquet [--eeg-only]");
 if(argc==4 && std::string(argv[3])!="--eeg-only")throw std::runtime_error("Unknown option");
 if(std::filesystem::exists(argv[2]))throw std::runtime_error("Output exists");
 parquet::FileDecryptionProperties::Builder db;
 auto props=parquet::default_reader_properties();props.file_decryption_properties(db.key_retriever(std::make_shared<Retriever>())->build());
 parquet::arrow::FileReaderBuilder builder;check(builder.OpenFile(argv[1],false,props));
 std::unique_ptr<parquet::arrow::FileReader> reader;check(builder.Build(&reader));
 std::shared_ptr<arrow::Table> table;
 if(argc==4){
  std::shared_ptr<arrow::Schema> schema;check(reader->GetSchema(&schema));
  std::vector<int> columns;
  for(int i=0;i<schema->num_fields();++i){auto n=schema->field(i)->name();
   if(n=="Timestamp"||n=="OriginalTimestamp"||n.rfind("EEG.",0)==0||n.rfind("CQ.",0)==0)columns.push_back(i);
  }
  check(reader->ReadTable(columns,&table));
 }else{check(reader->ReadTable(&table));}
 check(table->ValidateFull());
 auto result=arrow::io::FileOutputStream::Open(argv[2]);if(!result.ok())throw std::runtime_error(result.status().ToString());
 auto output=*result;check(parquet::arrow::WriteTable(*table,arrow::default_memory_pool(),output,65536));check(output->Close());
 std::cout<<"Authenticated read succeeded. Rows: "<<table->num_rows()<<" columns: "<<table->num_columns()<<"\n";
 return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}}
