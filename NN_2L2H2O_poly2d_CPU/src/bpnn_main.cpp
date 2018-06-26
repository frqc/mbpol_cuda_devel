

#include "bpnn_main.h"
#include <iomanip>

using namespace std;
using namespace MBbpnnPlugin;






template<typename T>
bpnn_t<T>::bpnn_t(): Gfunction_t<T>(), allNN_t<T>(), energy_(nullptr){} ;

template<typename T>
bpnn_t<T>::bpnn_t(string tag): Gfunction_t<T>(), allNN_t<T>(), energy_(nullptr){
     if (tag == "2h2o_default") {

          cerr << " === Initialize default 2B H2O model ... === " << endl;          

          this->insert_atom("O");
          this->insert_atom("H");
          this->insert_atom("H");
          this->insert_atom("O");
          this->insert_atom("H");
          this->insert_atom("H");

          this->load_seq_2h2o_default();
          this->load_paramfile_2h2o_default();
          this->load_scale_2h2o_default();

          this->init_allNNs(2, INFILE_2B, CHECKCHAR2);
          
          cerr << " === Model initialized successfully ! === " << endl;
     } else if (tag == "3h2o_default") {
          cerr << " === Initialize default 3B H2O model ... === " << endl;          

          this->insert_atom("O");
          this->insert_atom("H");
          this->insert_atom("H");
          this->insert_atom("O");
          this->insert_atom("H");
          this->insert_atom("H");
          this->insert_atom("O");
          this->insert_atom("H");
          this->insert_atom("H");          

          this->load_seq_3h2o_default();
          this->load_paramfile_3h2o_default();
          this->load_scale_3h2o_default();

          this->init_allNNs(2, INFILE_3B, CHECKCHAR2);
          
          cerr << " === Model initialized successfully ! === " << endl;

     };
} ;

template<typename T>
bpnn_t<T>::~bpnn_t(){
     if (energy_ != nullptr ) delete [] energy_ ; 
};





template<typename T>
T MBbpnnPlugin::get_eng_2h2o(size_t nd, std::vector<T>xyz1, std::vector<T>xyz2, std::vector<std::string> atoms1, std::vector<std::string> atoms2){ 

     string tag = "2h2o_default";
     static bpnn_t<T> bpnn_2h2o(tag);

     std::vector<T> allxyz;

     size_t a1 = (size_t) ( xyz1.size() / (3 * nd) ); 
     size_t a2 = (size_t) ( xyz2.size() / (3 * nd) ); 


     if ( ! atoms1.empty() ) {
          if (a1 != atoms1.size() ) cerr << " Molecule 1 type inconsistent! " << endl;
          if (a2 != atoms2.size() ) cerr << " Molecule 2 type inconsistent! " << endl;
          atoms1.insert(atoms1.end(), atoms2.begin(), atoms2.end() );
     }

     auto it1 = xyz1.begin();
     auto it2 = xyz2.begin();

     for(size_t i =0; i< nd; i++){
          for(int j = 0; j < a1; j++){
               allxyz.push_back(*it1++) ;
               allxyz.push_back(*it1++) ;
               allxyz.push_back(*it1++) ;
          }
          for(int j = 0; j < a2; j++){
               allxyz.push_back(*it2++) ;
               allxyz.push_back(*it2++) ;
               allxyz.push_back(*it2++) ;
          }               
     }

     bpnn_2h2o.load_xyz_and_type_from_vectors(nd, allxyz, atoms1) ; 

     bpnn_2h2o.make_G();
     bpnn_2h2o.cal_switch(2);

     if (bpnn_2h2o.energy_ != nullptr) delete[] bpnn_2h2o.energy_ ;

     bpnn_2h2o.energy_ = new T [bpnn_2h2o.NCLUSTER]();
     T * tmp = new T [bpnn_2h2o.NCLUSTER]() ;

     for(idx_t at = 0; at < bpnn_2h2o.NATOM; at ++){

          size_t tp_idx = bpnn_2h2o.TYPE_EACHATOM[at];

               bpnn_2h2o.nets[tp_idx].predict(*bpnn_2h2o.G[at], bpnn_2h2o.G_param_max_size[tp_idx], bpnn_2h2o.NCLUSTER, tmp );

               for (int i = 0; i < bpnn_2h2o.NCLUSTER; i++ ){
                    bpnn_2h2o.energy_[i] += tmp[i];
               }
          
     }

     delete [] tmp; 

     T energy = 0;

     for (size_t i = 0; i < bpnn_2h2o.NCLUSTER; i++ ){
          energy +=  bpnn_2h2o.energy_[i] * bpnn_2h2o.switch_factor[i];
          // cout << " Dimer " << i << " 's energy is " << bpnn_2h2o.energy_[i]* bpnn_2h2o.switch_factor[i] * (EUNIT) << endl;
     }
         
     // cout << " Total energy is "<< energy << endl;                         
     return energy*(EUNIT);
}


template<typename T>
T MBbpnnPlugin::get_eng_2h2o(size_t nd, std::vector<T>xyz1, std::vector<T>xyz2, std::vector<T> & grad1, std::vector<T>& grad2, std::vector<std::string> atoms1, std::vector<std::string> atoms2 ){ 

     string tag = "2h2o_default";
     static bpnn_t<T> bpnn_2h2o(tag);

     std::vector<T> allxyz;

     size_t a1 = (size_t) ( xyz1.size() / (3 * nd) ); 
     size_t a2 = (size_t) ( xyz2.size() / (3 * nd) ); 


     if ( ! atoms1.empty() ) {
          if (a1 != atoms1.size() ) cerr << " Molecule 1 type inconsistent! " << endl;
          if (a2 != atoms2.size() ) cerr << " Molecule 2 type inconsistent! " << endl;
          atoms1.insert(atoms1.end(), atoms2.begin(), atoms2.end() );
     }

     auto it1 = xyz1.begin();
     auto it2 = xyz2.begin();

     for(size_t i =0; i< nd; i++){
          for(int j = 0; j < a1; j++){
               allxyz.push_back(*it1++) ;
               allxyz.push_back(*it1++) ;
               allxyz.push_back(*it1++) ;
          }
          for(int j = 0; j < a2; j++){
               allxyz.push_back(*it2++) ;
               allxyz.push_back(*it2++) ;
               allxyz.push_back(*it2++) ;
          }               
     }

     bpnn_2h2o.load_xyz_and_type_from_vectors(nd, allxyz, atoms1) ; 

     bpnn_2h2o.make_G();
     bpnn_2h2o.cal_switch(2);



     if (bpnn_2h2o.energy_ != nullptr) delete[] bpnn_2h2o.energy_ ;

     bpnn_2h2o.energy_ = new T [bpnn_2h2o.NCLUSTER]();
     T * tmp = new T [bpnn_2h2o.NCLUSTER]() ;
     T * tmp_grd = nullptr;
     T** tmp_grd2= nullptr;

     std::vector<T**> dfdG;


     for(idx_t at = 0; at < bpnn_2h2o.NATOM; at ++){

          size_t tp_idx = bpnn_2h2o.TYPE_EACHATOM[at];
          
          bpnn_2h2o.nets[tp_idx].predict(*bpnn_2h2o.G[at], bpnn_2h2o.G_param_max_size[tp_idx], bpnn_2h2o.NCLUSTER, tmp );

          for (int i = 0; i < bpnn_2h2o.NCLUSTER; i++ ){
               bpnn_2h2o.energy_[i] += tmp[i];
          }

          // backwards on NN, with the switching factor included
          bpnn_2h2o.nets[tp_idx].backward(bpnn_2h2o.switch_factor, bpnn_2h2o.NCLUSTER, 1, tmp_grd );

          init_mtx_in_mem(tmp_grd2, bpnn_2h2o.G_param_max_size[tp_idx], nd) ;
          copy(tmp_grd, tmp_grd + nd * bpnn_2h2o.G_param_max_size[tp_idx],tmp_grd2[0] );

          if (tmp_grd != nullptr){
               delete [] tmp_grd;
               tmp_grd = nullptr;
          }
          dfdG.push_back(tmp_grd2);
          // tmp_grd
     }
     delete [] tmp; 
     if (tmp_grd != nullptr) delete[] tmp_grd;

     T energy = 0;

     for (size_t i = 0; i < bpnn_2h2o.NCLUSTER; i++ ){
          energy +=  bpnn_2h2o.energy_[i] * bpnn_2h2o.switch_factor[i];
          // cout << " Dimer " << i << " 's energy is " << bpnn_2h2o.energy_[i]*  bpnn_2h2o.switch_factor[i] * (EUNIT) << endl;
     }
         
     // cout << " Total energy is "<< energy << endl;        

     // save partially gradient       
     init_mtx_in_mem(bpnn_2h2o.dfdxyz , (size_t)(bpnn_2h2o.NATOM *3) , bpnn_2h2o.NCLUSTER);
     bpnn_2h2o.make_grd(dfdG);

     for (auto it= dfdG.begin(); it!= dfdG.end(); it++){
          clearMemo(*it);
     }

     // another part of gradient comes from switching function
     bpnn_2h2o.get_dfdx_from_switch(2, bpnn_2h2o.energy_);


     for(size_t i =0; i< bpnn_2h2o.NATOM*3; i++){
          for(size_t j=0; j < bpnn_2h2o.NCLUSTER; j++){
               bpnn_2h2o.dfdxyz[i][j] *= (EUNIT) ;
          }
     }


     T* grd = bpnn_2h2o.dfdxyz[0];
     for(size_t i =0; i< nd; i++){
          for(int j = 0; j < a1; j++){
               grad1.push_back(*grd++) ;
               grad1.push_back(*grd++) ;
               grad1.push_back(*grd++) ;
          }
          for(int j = 0; j < a2; j++){
               grad2.push_back(*grd++) ;
               grad2.push_back(*grd++) ;
               grad2.push_back(*grd++) ;
          }             
     }

     return energy*(EUNIT);
}




template<typename T>
T MBbpnnPlugin::get_eng_2h2o(const char* xyzfile, bool ifgrad ){ 

     static bpnn_t<T> bpnn_2h2o;
     bpnn_2h2o.load_xyzfile(xyzfile) ; 

     bpnn_2h2o.load_seq_2h2o_default();
     bpnn_2h2o.load_paramfile_2h2o_default();
     bpnn_2h2o.load_scale_2h2o_default();
     bpnn_2h2o.init_allNNs(2, INFILE_2B, CHECKCHAR2);

     bpnn_2h2o.make_G();
     bpnn_2h2o.cal_switch(2);

     if (bpnn_2h2o.energy_ != nullptr) delete[] bpnn_2h2o.energy_ ;

     bpnn_2h2o.energy_ = new T [bpnn_2h2o.NCLUSTER]();


     T * tmp = new T [bpnn_2h2o.NCLUSTER]() ;
     for(idx_t at = 0; at < bpnn_2h2o.NATOM; at ++){
          size_t tp_idx = bpnn_2h2o.TYPE_EACHATOM[at];
          bpnn_2h2o.nets[tp_idx].predict(*bpnn_2h2o.G[at], bpnn_2h2o.G_param_max_size[tp_idx], bpnn_2h2o.NCLUSTER, tmp );

          for (int i = 0; i < bpnn_2h2o.NCLUSTER; i++ ){
               bpnn_2h2o.energy_[i] += tmp[i];
          }
     }
     delete [] tmp; 

     T energy = 0;
     for (size_t i = 0; i < bpnn_2h2o.NCLUSTER; i++ ){
          energy +=  bpnn_2h2o.energy_[i] * bpnn_2h2o.switch_factor[i];
          // cout << " Dimer " << i << " 's energy is " << bpnn_2h2o.energy_[i]* bpnn_2h2o.switch_factor[i] * (EUNIT) << endl;
     }




     if(ifgrad){

          T * tmp_grd = nullptr;
          T** tmp_grd2= nullptr;

          std::vector<T**> dfdG;


          for(idx_t at = 0; at < bpnn_2h2o.NATOM; at ++){

               size_t tp_idx = bpnn_2h2o.TYPE_EACHATOM[at];
               
               // backwards on NN, with the switching factor included
               bpnn_2h2o.nets[tp_idx].backward(bpnn_2h2o.switch_factor, bpnn_2h2o.NCLUSTER, 1, tmp_grd );

               init_mtx_in_mem(tmp_grd2, bpnn_2h2o.G_param_max_size[tp_idx], bpnn_2h2o.NCLUSTER) ;
               copy(tmp_grd, tmp_grd + bpnn_2h2o.NCLUSTER * bpnn_2h2o.G_param_max_size[tp_idx],tmp_grd2[0] );

               if (tmp_grd != nullptr){
                    delete [] tmp_grd;
                    tmp_grd = nullptr;
               }
               dfdG.push_back(tmp_grd2);
               // tmp_grd
          }

          if (tmp_grd != nullptr) delete[] tmp_grd;   

          // save partially gradient       
          init_mtx_in_mem(bpnn_2h2o.dfdxyz , (size_t)(bpnn_2h2o.NATOM *3) , bpnn_2h2o.NCLUSTER);
          bpnn_2h2o.make_grd(dfdG);

          for (auto it= dfdG.begin(); it!= dfdG.end(); it++){
               clearMemo(*it);
          }

          // another part of gradient comes from switching function
          bpnn_2h2o.get_dfdx_from_switch(2, bpnn_2h2o.energy_);


          for(size_t i =0; i< bpnn_2h2o.NATOM*3; i++){
               for(size_t j=0; j < bpnn_2h2o.NCLUSTER; j++){
                    bpnn_2h2o.dfdxyz[i][j] *= (EUNIT) ;
               }
          }

          cout << " gradient is done, but not returned " << endl;
     }
     return energy*(EUNIT);
}




template<typename T>
T MBbpnnPlugin::get_eng_3h2o(const char* xyzfile, bool ifgrad ){ 

     static bpnn_t<T> bpnn_3h2o;
     bpnn_3h2o.load_xyzfile(xyzfile) ; 

     bpnn_3h2o.load_seq_3h2o_default();
     bpnn_3h2o.load_paramfile_3h2o_default();
     bpnn_3h2o.load_scale_3h2o_default();
     bpnn_3h2o.init_allNNs(2, INFILE_3B, CHECKCHAR2);

     bpnn_3h2o.make_G();
     bpnn_3h2o.cal_switch(3);

     if (bpnn_3h2o.energy_ != nullptr) delete[] bpnn_3h2o.energy_ ;

     bpnn_3h2o.energy_ = new T [bpnn_3h2o.NCLUSTER]();


     T * tmp = new T [bpnn_3h2o.NCLUSTER]() ;
     for(idx_t at = 0; at < bpnn_3h2o.NATOM; at ++){
          size_t tp_idx = bpnn_3h2o.TYPE_EACHATOM[at];
          bpnn_3h2o.nets[tp_idx].predict(*bpnn_3h2o.G[at], bpnn_3h2o.G_param_max_size[tp_idx], bpnn_3h2o.NCLUSTER, tmp );

          for (int i = 0; i < bpnn_3h2o.NCLUSTER; i++ ){
               bpnn_3h2o.energy_[i] += tmp[i];
          }
     }
     delete [] tmp; 

     T energy = 0;
     for (size_t i = 0; i < bpnn_3h2o.NCLUSTER; i++ ){
          energy +=  bpnn_3h2o.energy_[i] * bpnn_3h2o.switch_factor[i];
          // cout << " Dimer " << i << " 's energy is " << bpnn_3h2o.energy_[i]* bpnn_3h2o.switch_factor[i] * (EUNIT) << endl;

          // cout << " Dimer " << i << " 's energy is " << bpnn_3h2o.energy_[i]* bpnn_3h2o.switch_factor[i] *1 << endl;

     }




     if(ifgrad){

          T * tmp_grd = nullptr;
          T** tmp_grd2= nullptr;

          std::vector<T**> dfdG;


          for(idx_t at = 0; at < bpnn_3h2o.NATOM; at ++){

               size_t tp_idx = bpnn_3h2o.TYPE_EACHATOM[at];
               
               // backwards on NN, with the switching factor included
               bpnn_3h2o.nets[tp_idx].backward(bpnn_3h2o.switch_factor, bpnn_3h2o.NCLUSTER, 1, tmp_grd );

               init_mtx_in_mem(tmp_grd2, bpnn_3h2o.G_param_max_size[tp_idx], bpnn_3h2o.NCLUSTER) ;
               copy(tmp_grd, tmp_grd + bpnn_3h2o.NCLUSTER * bpnn_3h2o.G_param_max_size[tp_idx],tmp_grd2[0] );

               if (tmp_grd != nullptr){
                    delete [] tmp_grd;
                    tmp_grd = nullptr;
               }
               dfdG.push_back(tmp_grd2);
               // tmp_grd
          }

          if (tmp_grd != nullptr) delete[] tmp_grd;   

          // save partially gradient       
          init_mtx_in_mem(bpnn_3h2o.dfdxyz , (size_t)(bpnn_3h2o.NATOM *3) , bpnn_3h2o.NCLUSTER);
          bpnn_3h2o.make_grd(dfdG);

          for (auto it= dfdG.begin(); it!= dfdG.end(); it++){
               clearMemo(*it);
          }

          // another part of gradient comes from switching function
          bpnn_3h2o.get_dfdx_from_switch(2, bpnn_3h2o.energy_);


          for(size_t i =0; i< bpnn_3h2o.NATOM*3; i++){
               for(size_t j=0; j < bpnn_3h2o.NCLUSTER; j++){
                    bpnn_3h2o.dfdxyz[i][j] *= (EUNIT) ;
               }
          }

          cout << " gradient is done, but not returned " << endl;
     }
     return energy*(EUNIT);
}












template class bpnn_t<float>;
template class bpnn_t<double>;

template float MBbpnnPlugin::get_eng_2h2o<float>(size_t nd, std::vector<float>xyz1, std::vector<float>xyz2, std::vector<std::string> atoms1, std::vector<std::string> atoms2);

template double MBbpnnPlugin::get_eng_2h2o<double>(size_t nd, std::vector<double>xyz1, std::vector<double>xyz2, std::vector<std::string> atoms1, std::vector<std::string> atoms2);



template float MBbpnnPlugin::get_eng_2h2o<float>(size_t nd, std::vector<float>xyz1, std::vector<float>xyz2, std::vector<float>& grad1, std::vector<float>& grad2,std::vector<std::string> atoms1, std::vector<std::string> atoms2);

template double MBbpnnPlugin::get_eng_2h2o<double>(size_t nd, std::vector<double>xyz1, std::vector<double>xyz2, 
std::vector<double>& grad1, std::vector<double>& grad2,std::vector<std::string> atoms1, std::vector<std::string> atoms2);




template float MBbpnnPlugin::get_eng_2h2o<float>(const char* infile, bool ifgrad);

template double MBbpnnPlugin::get_eng_2h2o<double>(const char* infile, bool ifgrad);

template float MBbpnnPlugin::get_eng_3h2o<float>(const char* infile, bool ifgrad);

template double MBbpnnPlugin::get_eng_3h2o<double>(const char* infile, bool ifgrad);









int main_bak(int argc, const char* argv[]){

     cout << " usage: THIS.EXE 2|3 in.xyz if_grad[0|1]" << endl;

     if(argc >2 )  {
          bool ifgrad = false ;
          if(argc == 4 ) {
               if (atoi(argv[3]) == 1) ifgrad = true;
          }

          if ( atoi(argv[1]) == 2 ){
               get_eng_2h2o<double>(argv[2], ifgrad);
          } else if ( atoi(argv[1]) == 3 ) {
               // get_eng_3h2o(argv[2], ifgrad);
          }
     // } else {


     vector<double> xyz1, xyz2, grad1, grad2;
     double k = 0.001;
     vector<string> atoms;
     atoms.push_back("O");
     atoms.push_back("H");
     atoms.push_back("H");

     double X1[] = {     
 6.63713761738e-02 , 0.00000000000e+00 , 2.77747931775e-03,
-5.58841194785e-01 , 9.44755044560e-03 , 7.46468602271e-01,
-4.94520768565e-01 ,-9.44755044560e-03 ,-7.90549217078e-01
     };

     double X2[] = {     
-5.53091751468e-02 , 3.57455079421e-02  , 2.91048792936e+00,
 7.01247528930e-02 ,-7.30912395468e-01  , 3.49406182382e+00,
 8.07672042691e-01 , 1.63605212803e-01  , 2.48273588087e+00
     };


     double X3[] = {
 6.64009230786e-02 , 0.00000000000e+00 , 1.94714685775e-03,
-5.49462991968e-01 ,-8.87993450068e-04 , 7.53457194072e-01,
-5.04367902227e-01 , 8.87993450068e-04 ,-7.84359829444e-01
     };

     double X4[] = {
-5.76867978356e-02 ,-4.88696559854e-03  , 4.23354333315e+00,
 7.66626879677e-02 , 1.05368656403e-01  , 5.18949857004e+00,
 8.38868707197e-01 ,-2.78089616304e-02  , 3.85975287053e+00
     };

     double dX1[9];
     double dX2[9];



     for(int i=0; i <9 ; i++){
          xyz1.push_back(X1[i]);
          xyz2.push_back(X2[i]);
     }

     size_t n = 1 ;
     double e1, e2;
     e1 = get_eng_2h2o(n, xyz1, xyz2) ;
     e2 = get_eng_2h2o(n, xyz1, xyz2, grad1, grad2) ;


     // for( int i=0; i <9; i++){
     //      {
     //           vector<double> x1, x2;
     //           x1 = xyz1;
     //           x2 = xyz2;
     //           double d = x1[i] * k;
     //           x1[i] += d;
     //           double e = get_eng_2h2o(n, x1, x2) ; 
     //           double de = e - e1;
     //           dX1[i] = de / d; 
     //      };

     //      {
     //           vector<double> x1, x2;
     //           x1 = xyz1;
     //           x2 = xyz2;
     //           double d = x2[i] * k;
     //           x2[i] += d;
     //           double e = get_eng_2h2o(n, x1, x2) ; 
     //           double de = e - e1;
     //           dX2[i] = de / d; 
     //      };
     // }

     cout << " Energy is " << e1 << " and " << e2 << " wo/w grad respectively, and reference energy is: 2.717692114 " << endl;


     // cout << " Cal gradient(above) VS gradient by input(mid) VS reference graident(bot) is: " << endl;
     // for(auto it=grad1.begin(); it!= grad1.end(); it++){
     //      cout << setw(12) <<*it << " ";
     // }
     // for(auto it=grad2.begin(); it!= grad2.end(); it++){
     //      cout << setw(12) <<*it << " ";
     // }     
     // cout << endl;
     // for(int i=0; i < 9; i++){
     //      cout << setw(12) << dX1[i] << " ";
     // }     
     // for(int i=0; i < 9; i++){
     //      cout << setw(12) << dX2[i] << " ";
     // }          
     // cout << endl;
     // cout << "-0.724757268 -0.130047727 -3.143973336 -1.617402502 -0.718120693 -5.651154603 -0.075997713  0.355257790 -1.548671998  0.971052895  1.943847983  6.554913834  0.592645772 -1.069982368  0.737319658  0.854458816 -0.380954985  3.051566444" << endl;




     // xyz1.clear();
     // xyz2.clear();
     // grad1.clear();
     // grad2.clear();

     for(int i=0; i <9 ; i++){
          xyz1.push_back(X3[i]);
          xyz2.push_back(X4[i]);
     }
     n = 2;
     e1 = get_eng_2h2o(n, xyz1, xyz2) ;
     e2 = get_eng_2h2o(n, xyz1, xyz2, grad1, grad2) ;

     // for( int i=0; i <9; i++){
     //      {
     //           vector<double> x1, x2;
     //           x1 = xyz1;
     //           x2 = xyz2;
     //           double d = x1[i] * k;
     //           x1[i] += d;
     //           double e = get_eng_2h2o(n, x1, x2) ; 
     //           double de = e - e1;
     //           dX1[i] = de / d; 
     //      };

     //      {
     //           vector<double> x1, x2;
     //           x1 = xyz1;
     //           x2 = xyz2;
     //           double d = x2[i] * k;
     //           x2[i] += d;
     //           double e = get_eng_2h2o(n, x1, x2) ; 
     //           double de = e - e1;
     //           dX2[i] = de / d; 
     //      };
     // }

     cout << " Energy is " << e1 << " and " << e2 << " wo/w grad respectively, and reference energy is: 0.090248572 " << endl;


     // cout << " Cal gradient(above) VS gradient by input(mid) VS reference graident(bot) is: " << endl;
     // for(auto it=grad1.begin(); it!= grad1.end(); it++){
     //      cout << setw(12) <<*it << " ";
     // }
     // for(auto it=grad2.begin(); it!= grad2.end(); it++){
     //      cout << setw(12) <<*it << " ";
     // }     
     // cout << endl;
     // for(int i=0; i < 9; i++){
     //      cout << setw(12) << dX1[i] << " ";
     // }     
     // for(int i=0; i < 9; i++){
     //      cout << setw(12) << dX2[i] << " ";
     // }          
     // cout << endl;
     // cout << " 0.138880070 -0.011111458  0.084297440 -0.202194333  0.033384194 -0.291813818 -0.043120857 -0.007868340  0.097843290  0.349070577 -0.025231151  0.079072851 -0.119690823  0.008111216 -0.165551883 -0.122944634  0.002715540  0.196152120" << endl;


     }
     return 0;
}

int main(int argc, const char* argv[]){

     cout << " usage: THIS.EXE 2|3 in.xyz if_grad[0|1]" << endl;

     if(argc >2 )  {
          bool ifgrad = false ;
          if(argc == 4 ) {
               if (atoi(argv[3]) == 1) ifgrad = true;
          }

          if ( atoi(argv[1]) == 2 ){
               get_eng_2h2o<double>(argv[2], ifgrad);
          } else if ( atoi(argv[1]) == 3 ) {
               get_eng_3h2o<double>(argv[2], ifgrad);
          }





     }

     return 0;
}