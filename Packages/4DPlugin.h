/* --------------------------------------------------------------------------------
 #
 #	4DPlugin.h
 #	source generated by 4D Plugin Wizard
 #	Project : Packages
 #	author : miyako
 #	2015/05/28
 #
 # --------------------------------------------------------------------------------*/



// --- PATH
void PATH_SET_PACKAGE_BIT(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_Get_package_bit(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_Is_package(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_SET_EXTENSION_HIDDEN(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_Is_extension_hidden(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_Get_localized_name(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_SET_HIDDEN(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_Is_hidden(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_SET_ICON(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_Get_icon(sLONG_PTR *pResult, PackagePtr pParams);
void PATH_Get_display_name(sLONG_PTR *pResult, PackagePtr pParams);

#ifndef NSFoundationVersionNumber10_8
#define NSFoundationVersionNumber10_8 945.00
#endif