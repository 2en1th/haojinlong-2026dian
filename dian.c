#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define NANOSVG_IMPLEMENTATION
#include "nanosvg.h"

#define NANOSVGRAST_IMPLEMENTATION
#include "nanosvgrast.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

// 计算输出尺寸，短边>=1000px，保持长宽比
void calculate_output_size(float svg_width, float svg_height, 
                           int *out_width, int *out_height) {
    float min_side = fminf(svg_width, svg_height);
    if (min_side <= 0) min_side = 1.0f;
    
    float scale = 1000.0f / min_side;
    
    *out_width = (int)(svg_width * scale + 0.5f);
    *out_height = (int)(svg_height * scale + 0.5f);
    
    if (*out_width < 1000) *out_width = 1000;
    if (*out_height < 1000) *out_height = 1000;
}

// 生成输出文件名
char* generate_output_path(const char* input_path) {
    size_t len = strlen(input_path);
    char* output_path = (char*)malloc(len + 5);
    if (!output_path) return NULL;
    
    strcpy(output_path, input_path);
    char* dot = strrchr(output_path, '.');
    if (dot) {
        strcpy(dot, ".png");
    } else {
        strcat(output_path, ".png");
    }
    
    return output_path;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        fprintf(stderr, "用法：%s <input.svg>\n", argv[0]);
        return 1;
    }
    
    const char* input_path = argv[1];
    
    // 1. 解析 SVG
    printf("正在解析 SVG: %s\n", input_path);
    struct NSVGimage* image = nsvgParseFromFile(input_path, "px", 96.0f);
    if (!image) {
        fprintf(stderr, "错误：无法解析 SVG 文件\n");
        return 1;
    }
    
    printf("画布尺寸：%.2f x %.2f\n", image->width, image->height);
    
    // 2. 计算输出尺寸
    int out_width = 0, out_height = 0;
    calculate_output_size(image->width, image->height, &out_width, &out_height);
    printf("输出尺寸：%dx%d\n", out_width, out_height);
    
    // 3. 创建光栅化器
    struct NSVGrasterizer* rast = nsvgCreateRasterizer();
    if (!rast) {
        fprintf(stderr, "错误：无法创建光栅化器\n");
        nsvgDelete(image);
        return 1;
    }
    
    // 4. 渲染 - 【修复】使用 9 参数版本
    printf("正在渲染...\n");
    float scale = (float)out_width / image->width;
    
    // 新版本 API：需要传入输出宽高指针和 stride
    int stride = out_width * 4;
    unsigned char* img_data = (unsigned char*)malloc(out_width * out_height * 4);
    if (!img_data) {
        fprintf(stderr, "错误：内存分配失败\n");
        nsvgDeleteRasterizer(rast);
        nsvgDelete(image);
        return 1;
    }
    
   // 9 参数版本：rast, image, tx, ty, scale, img_data, w, h, stride
    nsvgRasterize(rast, image, 0, 0, scale, img_data, out_width, out_height, stride);
    
    // 5. 保存 PNG
    char* output_path = generate_output_path(input_path);
    printf("正在保存：%s\n", output_path);
    
    if (stbi_write_png(output_path, out_width, out_height, 4, img_data, stride) == 0) {
        fprintf(stderr, "错误：保存 PNG 失败\n");
        free(output_path);
        free(img_data);
        nsvgDeleteRasterizer(rast);
        nsvgDelete(image);
        return 1;
    }
    
    printf("\n完成！输出文件：%s\n", output_path);
    printf("文件大小：约 %d KB\n", (out_width * out_height * 4) / 1024);
    
    // 6. 清理资源
    free(output_path);
    free(img_data);
    nsvgDeleteRasterizer(rast);
    nsvgDelete(image);
    
    return 0;
}