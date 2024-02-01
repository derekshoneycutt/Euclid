const path = require('path');
const webpack = require('webpack');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const HtmlWebpackPlugin = require('html-webpack-plugin');

const build_mode = 'production';

module.exports = {
    entry: './web/euclid.js',

    output: {
        path: path.resolve(__dirname, 'build/dist'),
        publicPath: '',
        filename: 'bundle.js'
    },

    module: {
        rules: [
            {
                test: /\.js$/,
                exclude: /(node_modules)/,
                use: {
                    loader: 'babel-loader',
                    options: {
                        presets: ['@babel/preset-env']
                    }
                }
            },
            {
                test: /\.(sa|sc|c)ss$/,
                use: [
                    {
                        loader: MiniCssExtractPlugin.loader
                    },
                    {
                        loader: 'css-loader'
                    },
                    {
                        loader: 'postcss-loader'
                    },
                    {
                        loader: 'sass-loader',
                        options: {
                            implementation: require('sass'),
                            webpackImporter: false,
                            sassOptions: {
                                includePaths: [
                                    path.resolve(__dirname, 'node_modules')
                                ]
                            }
                        }
                    }
                ]
            },
            {
                test: /\.(png|jpe?g|gif|svg)$/,
                use: [
                    {
                        loader: 'file-loader',
                        options: {
                            outputPath: 'images'
                        }
                    }
                ]
            }
        ]
    },

    plugins: [
        new MiniCssExtractPlugin({
            filename: 'bundle.css'
        }),

        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_001-Point.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_002-Line.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_003-LineExtremities.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_004-StraightLine.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_005-Surface.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_006-SurfaceExtremities.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_007-PlaneSurface.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_008-PlaneAngle.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_009-RectilinealAngle.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_010-RightPerpendicular.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_011-ObtuseAngle.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_012-AcuteAngle.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_013-Boundary.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_014-Figure.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_015-Circle.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_016-Center.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_017-Diameter.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_018-Semicircle.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Postulates_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_CommonNotions_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Propositions_index.html' }),
    ],

    mode: build_mode
};
